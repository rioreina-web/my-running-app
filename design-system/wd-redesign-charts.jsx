/* global React, wdStore, WK, WX, REP_PLAN, HR_ZONES, zoneOf, STREAM, REP_RECOVERY, TIZ, COMPARE, RECENT_AVG, fmtClock, fmtPaceVal, paceUnit, distVal, distUnit, elevVal, elevUnit, wd */
/* ════════════════════════════════════════════════════════════════════
   WORKOUT DETAIL · REDESIGN — CHART KIT
   Dense, interval-aware telemetry. Every chart reads the tweaks store
   (units / weather-adjust / color-by-zone).
   ════════════════════════════════════════════════════════════════════ */

const COR = "var(--coral)";
const INK = "var(--ink)";
const INK2 = "var(--ink-2)";
const INK3 = "var(--ink-3)";
const RULE = "var(--rule)";

/* map a sample index → x in a plot */
const xOfSec = (sec, x0, w) => x0 + (sec / STREAM.totalSec) * w;

/* ─── 1 · REP CHART (HERO) ───────────────────────────────────────────
   Each rep is a bar: WIDTH ∝ distance, HEIGHT ∝ speed (faster = taller),
   rest gaps to scale. HR plotted as a line riding the tops. Pace-zone
   dashed reference (target). Color-by-zone optional. */
function RepChart({ height = 230 }) {
  const st = wdStore.use();
  const W = 340, H = height;
  const PAD_L = 34, PAD_R = 10, PAD_T = 30, PAD_B = 34;
  const plotW = W - PAD_L - PAD_R, plotH = H - PAD_T - PAD_B;

  // total timeline of work + rests (exclude warmup/cooldown) so reps fill width
  const items = [];
  REP_PLAN.forEach((r) => {
    items.push({ type: "rep", ...r, dur: Math.round(r.distMi * r.paceSec) });
    if (r.rest) items.push({ type: "rest", dur: r.rest });
  });
  const totalDur = items.reduce((s, it) => s + it.dur, 0);

  // pace scale (faster paces → taller). invert: smaller sec = taller
  const paceMin = 300, paceMax = 340; // sec/mi window for work reps
  const barH = (p) => ((paceMax - p) / (paceMax - paceMin)) * (plotH - 30) + 24;
  // HR scale
  const hrMin = 140, hrMax = 180;
  const yHr = (h) => PAD_T + (plotH) - ((h - hrMin) / (hrMax - hrMin)) * (plotH);

  // lay items along x by duration
  let cursor = PAD_L;
  const laid = items.map((it) => {
    const w = (it.dur / totalDur) * plotW;
    const o = { ...it, x: cursor, w };
    cursor += w;
    return o;
  });
  const reps = laid.filter((it) => it.type === "rep");

  const fastest = Math.min(...REP_PLAN.map((r) => r.paceSec));
  const hrLine = reps.map((r) => ({ x: r.x + r.w / 2, y: yHr(r.hr) }));

  return (
    <svg viewBox={`0 0 ${W} ${H}`} style={{ width: "100%", height, display: "block" }}>
      {/* target pace reference */}
      {[305, 315, 325].map((p) => (
        <g key={p}>
          <line x1={PAD_L} x2={PAD_L + plotW} y1={PAD_T + plotH - barH(p)} y2={PAD_T + plotH - barH(p)}
            stroke={RULE} strokeWidth="0.5" strokeDasharray="2 3" />
          <text x={PAD_L - 5} y={PAD_T + plotH - barH(p) + 3} textAnchor="end"
            fontFamily="var(--font-mono)" fontSize="7.5" fill={INK3}>{fmtClock(st.units === "km" ? p / 1.60934 : p)}</text>
        </g>
      ))}
      {/* baseline */}
      <line x1={PAD_L} x2={PAD_L + plotW} y1={PAD_T + plotH} y2={PAD_T + plotH} stroke={RULE} strokeWidth="0.75" />

      {/* rest gaps */}
      {laid.filter((it) => it.type === "rest").map((it, i) => (
        <g key={`rest${i}`}>
          <rect x={it.x} y={PAD_T} width={it.w} height={plotH} fill={INK3} opacity="0.05" />
          <text x={it.x + it.w / 2} y={PAD_T + plotH + 11} textAnchor="middle"
            fontFamily="var(--font-mono)" fontSize="7" fill={INK3}>{it.dur}s</text>
        </g>
      ))}

      {/* rep bars */}
      {reps.map((r) => {
        const h = barH(r.paceSec);
        const isFast = r.paceSec === fastest;
        const col = st.colorByZone ? zoneOf(r.hr).color : (isFast ? COR : INK2);
        return (
          <g key={r.i}>
            <rect x={r.x + 1.5} y={PAD_T + plotH - h} width={r.w - 3} height={h}
              fill={col} opacity={st.colorByZone ? 0.9 : (isFast ? 1 : 0.82)} rx="1" />
            {/* pace label */}
            <text x={r.x + r.w / 2} y={PAD_T + plotH - h - 5} textAnchor="middle"
              fontFamily="var(--font-mono)" fontSize="10.5" fontWeight="600"
              fill={st.colorByZone ? INK : col}>{fmtPaceVal(r.paceSec, st.units, st.weatherAdjust)}</text>
            {/* rep label + distance */}
            <text x={r.x + r.w / 2} y={PAD_T + plotH + 11} textAnchor="middle"
              fontFamily="var(--font-mono)" fontSize="8" fontWeight="600" fill={INK}>{r.label}</text>
            <text x={r.x + r.w / 2} y={PAD_T + plotH + 21} textAnchor="middle"
              fontFamily="var(--font-mono)" fontSize="7" fill={INK3}>
              {distVal(r.distMi, st.units).toFixed(2)}{distUnit(st.units)}
            </text>
          </g>
        );
      })}

      {/* HR line over bars */}
      <polyline points={hrLine.map((p) => `${p.x.toFixed(1)},${p.y.toFixed(1)}`).join(" ")}
        fill="none" stroke={INK} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" opacity="0.85" />
      {hrLine.map((p, i) => (
        <g key={i}>
          <circle cx={p.x} cy={p.y} r="2.6" fill="var(--paper)" stroke={INK} strokeWidth="1.2" />
          <text x={p.x} y={p.y - 6} textAnchor="middle" fontFamily="var(--font-mono)" fontSize="7.5" fill={INK2}>{reps[i].hr}</text>
        </g>
      ))}

      {/* legend */}
      <g transform={`translate(${PAD_L}, 12)`}>
        <rect x="0" y="-7" width="9" height="9" fill={COR} rx="1" />
        <text x="13" y="1" fontFamily="var(--font-mono)" fontSize="8" fill={INK2} letterSpacing="0.06em">REP PACE · TALLER = FASTER</text>
        <circle cx="208" cy="-2" r="3" fill="var(--paper)" stroke={INK} strokeWidth="1.2" />
        <text x="216" y="1" fontFamily="var(--font-mono)" fontSize="8" fill={INK2} letterSpacing="0.06em">AVG HR</text>
      </g>
    </svg>
  );
}

/* ─── 2 · HR ZONE TIMELINE ───────────────────────────────────────────
   HR over the whole session, zone bands shaded, rep windows highlighted. */
function HRZoneTimeline({ height = 150 }) {
  const W = 340, H = height;
  const PAD_L = 28, PAD_R = 8, PAD_T = 8, PAD_B = 16;
  const plotW = W - PAD_L - PAD_R, plotH = H - PAD_T - PAD_B;
  const yMin = 90, yMax = 182;
  const y = (v) => PAD_T + plotH - ((v - yMin) / (yMax - yMin)) * plotH;
  const x = (sec) => xOfSec(sec, PAD_L, plotW);
  const path = STREAM.hr.map((v, i) => `${i === 0 ? "M" : "L"} ${x(STREAM.time[i]).toFixed(1)} ${y(v).toFixed(1)}`).join(" ");

  return (
    <svg viewBox={`0 0 ${W} ${H}`} style={{ width: "100%", height, display: "block" }}>
      {/* zone bands */}
      {HR_ZONES.map((z) => {
        const top = y(Math.min(z.hi, yMax)), bot = y(Math.max(z.lo, yMin));
        if (bot <= top) return null;
        return <rect key={z.id} x={PAD_L} y={top} width={plotW} height={bot - top} fill={z.color} opacity="0.08" />;
      })}
      {HR_ZONES.slice(1).map((z) => (
        <line key={z.id} x1={PAD_L} x2={PAD_L + plotW} y1={y(z.lo)} y2={y(z.lo)} stroke={RULE} strokeWidth="0.4" />
      ))}
      {[120, 150, 175].map((v) => (
        <text key={v} x={PAD_L - 4} y={y(v) + 3} textAnchor="end" fontFamily="var(--font-mono)" fontSize="7.5" fill={INK3}>{v}</text>
      ))}
      {/* rep windows */}
      {STREAM.repBands.filter((b) => b.kind === "rep").map((b) => (
        <g key={b.rep}>
          <rect x={x(b.startSec)} y={PAD_T} width={x(b.endSec) - x(b.startSec)} height={plotH} fill={COR} opacity="0.07" />
          <text x={(x(b.startSec) + x(b.endSec)) / 2} y={PAD_T + 8} textAnchor="middle"
            fontFamily="var(--font-mono)" fontSize="7" fill={COR} opacity="0.8">{b.rep}</text>
        </g>
      ))}
      <path d={path} fill="none" stroke={INK} strokeWidth="1.1" strokeLinejoin="round" opacity="0.85" />
      {/* x ticks */}
      {[0, 0.25, 0.5, 0.75, 1].map((f) => (
        <text key={f} x={PAD_L + f * plotW} y={H - 4} textAnchor={f === 0 ? "start" : f === 1 ? "end" : "middle"}
          fontFamily="var(--font-mono)" fontSize="7" fill={INK3}>{fmtClock(f * STREAM.totalSec)}</text>
      ))}
    </svg>
  );
}

/* ─── 3 · PACE / VELOCITY TRACE ─────────────────────────────────────── */
function PaceTrace({ height = 120 }) {
  const st = wdStore.use();
  const W = 340, H = height;
  const PAD_L = 32, PAD_R = 8, PAD_T = 8, PAD_B = 16;
  const plotW = W - PAD_L - PAD_R, plotH = H - PAD_T - PAD_B;
  const pmin = 290, pmax = 620; // sec/mi (faster up)
  const y = (v) => PAD_T + ((v - pmin) / (pmax - pmin)) * plotH;
  const x = (sec) => xOfSec(sec, PAD_L, plotW);
  // light smoothing
  const sm = STREAM.pace.map((_, i) => {
    const a = STREAM.pace.slice(Math.max(0, i - 3), i + 4);
    return a.reduce((s, v) => s + v, 0) / a.length;
  });
  const path = sm.map((v, i) => `${i === 0 ? "M" : "L"} ${x(STREAM.time[i]).toFixed(1)} ${y(v).toFixed(1)}`).join(" ");
  return (
    <svg viewBox={`0 0 ${W} ${H}`} style={{ width: "100%", height, display: "block" }}>
      {[330, 420, 540].map((v) => (
        <g key={v}>
          <line x1={PAD_L} x2={PAD_L + plotW} y1={y(v)} y2={y(v)} stroke={RULE} strokeWidth="0.4" />
          <text x={PAD_L - 4} y={y(v) + 3} textAnchor="end" fontFamily="var(--font-mono)" fontSize="7.5" fill={INK3}>
            {fmtClock(st.units === "km" ? v / 1.60934 : v)}
          </text>
        </g>
      ))}
      {STREAM.repBands.filter((b) => b.kind === "rep").map((b) => (
        <rect key={b.rep} x={x(b.startSec)} y={PAD_T} width={x(b.endSec) - x(b.startSec)} height={plotH} fill={COR} opacity="0.07" />
      ))}
      <path d={path} fill="none" stroke={COR} strokeWidth="1.2" strokeLinejoin="round" />
      <text x={PAD_L + plotW} y={PAD_T + 9} textAnchor="end" fontFamily="var(--font-mono)" fontSize="7.5" fill={INK3} letterSpacing="0.08em">
        SMOOTHED 14s · {paceUnit(st.units)}
      </text>
    </svg>
  );
}

/* ─── 4 · CADENCE STRIP ─────────────────────────────────────────────── */
function CadenceStrip({ height = 70 }) {
  const W = 340, H = height, PAD_L = 28, PAD_R = 8, PAD = 8;
  const plotW = W - PAD_L - PAD_R, plotH = H - PAD * 2;
  const min = 150, max = 195;
  const x = (sec) => xOfSec(sec, PAD_L, plotW);
  const y = (v) => PAD + plotH - ((v - min) / (max - min)) * plotH;
  const path = STREAM.cad.map((v, i) => `${i === 0 ? "M" : "L"} ${x(STREAM.time[i]).toFixed(1)} ${y(v).toFixed(1)}`).join(" ");
  const avg = Math.round(STREAM.cad.reduce((s, v) => s + v, 0) / STREAM.cad.length);
  return (
    <svg viewBox={`0 0 ${W} ${H}`} style={{ width: "100%", height, display: "block" }}>
      {STREAM.repBands.filter((b) => b.kind === "rep").map((b) => (
        <rect key={b.rep} x={x(b.startSec)} y={PAD} width={x(b.endSec) - x(b.startSec)} height={plotH} fill={COR} opacity="0.06" />
      ))}
      <line x1={PAD_L} x2={PAD_L + plotW} y1={y(avg)} y2={y(avg)} stroke={INK2} strokeWidth="0.6" strokeDasharray="3 3" opacity="0.5" />
      <text x={PAD_L - 4} y={y(186) + 3} textAnchor="end" fontFamily="var(--font-mono)" fontSize="7.5" fill={INK3}>186</text>
      <path d={path} fill="none" stroke={INK2} strokeWidth="1" opacity="0.8" strokeLinejoin="round" />
      <text x={PAD_L + plotW} y={PAD + 8} textAnchor="end" fontFamily="var(--font-mono)" fontSize="7.5" fill={INK2} letterSpacing="0.08em">AVG {avg} SPM</text>
    </svg>
  );
}

/* ─── 5 · ELEVATION + GRADE PROFILE ─────────────────────────────────── */
function ElevGradeProfile({ height = 88 }) {
  const st = wdStore.use();
  const W = 340, H = height, PAD_L = 28, PAD_R = 8, PAD_T = 8, PAD_B = 14;
  const plotW = W - PAD_L - PAD_R, plotH = H - PAD_T - PAD_B;
  const altFt = STREAM.alt.map((m) => m * 3.281);
  const min = Math.min(...altFt), max = Math.max(...altFt);
  const x = (sec) => xOfSec(sec, PAD_L, plotW);
  const y = (v) => PAD_T + plotH - ((v - min) / (max - min || 1)) * plotH;
  const path = altFt.map((v, i) => `${i === 0 ? "M" : "L"} ${x(STREAM.time[i]).toFixed(1)} ${y(v).toFixed(1)}`).join(" ");
  const area = `${path} L ${x(STREAM.time[STREAM.time.length - 1]).toFixed(1)} ${PAD_T + plotH} L ${x(0)} ${PAD_T + plotH} Z`;
  // grade-tinted segments (steep up = coral, down = green)
  return (
    <svg viewBox={`0 0 ${W} ${H}`} style={{ width: "100%", height, display: "block" }}>
      {altFt.map((v, i) => {
        if (i === 0) return null;
        const g = STREAM.grade[i];
        const col = g > 1.5 ? COR : g < -1.5 ? "#4A9E6B" : INK3;
        const op = Math.min(0.5, Math.abs(g) / 8 + 0.08);
        return <rect key={i} x={x(STREAM.time[i - 1])} y={PAD_T} width={x(STREAM.time[i]) - x(STREAM.time[i - 1]) + 0.5} height={plotH} fill={col} opacity={op} />;
      })}
      <path d={area} fill={INK} opacity="0.06" />
      <path d={path} fill="none" stroke={INK} strokeWidth="0.9" opacity="0.55" />
      <text x={PAD_L - 4} y={y(max) + 3} textAnchor="end" fontFamily="var(--font-mono)" fontSize="7.5" fill={INK3}>{elevVal(Math.round(max), st.units)}</text>
      <text x={PAD_L + plotW} y={H - 3} textAnchor="end" fontFamily="var(--font-mono)" fontSize="7.5" fill={INK3} letterSpacing="0.08em">
        +{elevVal(WK.elevGainFt, st.units)}{elevUnit(st.units)} GAIN · GRADE-TINTED
      </text>
    </svg>
  );
}

/* ─── 6 · REP HR RECOVERY (small multiples) ─────────────────────────── */
function RepRecovery() {
  return (
    <div style={{ display: "grid", gridTemplateColumns: `repeat(${REP_RECOVERY.length}, 1fr)`, gap: 6, marginTop: 8 }}>
      {REP_RECOVERY.map((r) => {
        const W = 48, H = 34, min = 130, max = 180;
        const xs = (i) => (i / (r.pts.length - 1)) * W;
        const ys = (v) => H - ((v - min) / (max - min)) * H;
        const path = r.pts.map((v, i) => `${i === 0 ? "M" : "L"} ${xs(i).toFixed(1)} ${ys(v).toFixed(1)}`).join(" ");
        const strong = r.drop >= 36;
        return (
          <div key={r.rep} style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 3, paddingBottom: 5, borderBottom: `1px solid ${RULE}` }}>
            <span style={{ ...wd.eyebrowSm, fontSize: 8, color: INK3 }}>R{r.rep}</span>
            <svg viewBox={`0 0 ${W} ${H}`} style={{ width: "100%", height: 26 }} preserveAspectRatio="none">
              <path d={path} fill="none" stroke={strong ? COR : INK2} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
            <span style={{ ...wd.mono, fontSize: 11, fontWeight: 600, color: strong ? COR : INK }}>−{r.drop}</span>
            <span style={{ ...wd.eyebrowSm, fontSize: 7.5, color: INK3 }}>bpm/60s</span>
          </div>
        );
      })}
    </div>
  );
}

/* ─── 7 · TIME IN ZONE (stacked bar + legend) ───────────────────────── */
function TimeInZoneBar() {
  const total = Object.values(TIZ).reduce((a, b) => a + b, 0);
  return (
    <div>
      <div style={{ display: "flex", height: 20, marginTop: 8, border: `1px solid ${RULE}` }}>
        {HR_ZONES.map((z) => {
          const pct = ((TIZ[z.id] || 0) / total) * 100;
          if (pct < 0.4) return null;
          const main = z.id === "Z4";
          return <div key={z.id} title={`${z.name} ${Math.round(pct)}%`} style={{ width: `${pct}%`, background: z.color, opacity: main ? 1 : 0.5, borderRight: "1px solid var(--paper)" }} />;
        })}
      </div>
      <div style={{ marginTop: 10, display: "grid", gridTemplateColumns: "repeat(5, 1fr)", gap: 6 }}>
        {HR_ZONES.map((z) => {
          const sec = TIZ[z.id] || 0, pct = (sec / total) * 100, main = z.id === "Z4";
          return (
            <div key={z.id} style={{ display: "flex", flexDirection: "column", gap: 2 }}>
              <div style={{ display: "flex", alignItems: "center", gap: 4 }}>
                <span style={{ width: 6, height: 6, background: z.color, opacity: main ? 1 : 0.5 }} />
                <span style={{ ...wd.eyebrowSm, color: main ? INK : INK3 }}>{z.id}</span>
              </div>
              <span style={{ ...wd.mono, fontSize: 12, fontWeight: 600, color: main ? COR : INK2 }}>{fmtClock(sec)}</span>
              <span style={{ ...wd.eyebrowSm, fontSize: 7.5 }}>{Math.round(pct)}%</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

/* ─── 8 · SPLITS / REP TABLE ─────────────────────────────────────────
   Diverging pace bar anchored to TARGET pace (faster = coral, right of
   center; slower = gray, left). Δ-vs-target column. Rest jogs shown as
   interstitial rows so the splits read as the full session structure.
   Totals footer. */
const SPLIT_COLS = "18px 26px 1fr 50px 36px 30px 32px";
function RepTable() {
  const st = wdStore.use();
  const fastest = Math.min(...REP_PLAN.map((r) => r.paceSec));
  const target = WK.avgWorkPaceSec;     // session target pace (sec/mi)
  const DEV = 14;                        // ± sec mapped to half the bar
  const restById = {};
  REP_RECOVERY.forEach((rr) => { restById[rr.rep] = rr; });

  // totals
  const totDist = REP_PLAN.reduce((s, r) => s + r.distMi, 0);
  const avgHr = Math.round(REP_PLAN.reduce((s, r) => s + r.hr, 0) / REP_PLAN.length);
  const avgCad = Math.round(REP_PLAN.reduce((s, r) => s + r.cad, 0) / REP_PLAN.length);

  const Head = () => (
    <div style={{ display: "grid", gridTemplateColumns: SPLIT_COLS, gap: 8, padding: "7px 0 5px", borderBottom: `1px solid ${RULE}` }}>
      <span style={{ ...wd.eyebrowSm, textAlign: "right" }}>#</span>
      <span style={wd.eyebrowSm}>REP</span>
      <span style={{ ...wd.eyebrowSm, textAlign: "center", whiteSpace: "nowrap" }}>◂ SLOW · FAST ▸</span>
      <span style={{ ...wd.eyebrowSm, textAlign: "right" }}>PACE</span>
      <span style={{ ...wd.eyebrowSm, textAlign: "right" }}>Δ TGT</span>
      <span style={{ ...wd.eyebrowSm, textAlign: "right" }}>HR</span>
      <span style={{ ...wd.eyebrowSm, textAlign: "right" }}>CAD</span>
    </div>
  );

  return (
    <div>
      <Head />
      {REP_PLAN.map((r, idx) => {
        const isFast = r.paceSec === fastest;
        const delta = r.paceSec - target;        // <0 = faster than target
        const faster = delta <= 0;
        const mag = Math.min(1, Math.abs(delta) / DEV);
        const col = st.colorByZone ? zoneOf(r.hr).color : faster ? COR : INK2;
        const rest = restById[r.i];
        return (
          <React.Fragment key={r.i}>
            <div style={{ display: "grid", gridTemplateColumns: SPLIT_COLS, gap: 8, alignItems: "center", padding: "8px 0 7px" }}>
              <span style={{ ...wd.eyebrowSm, color: isFast ? COR : INK3, textAlign: "right" }}>{r.i}</span>
              <div style={{ display: "flex", flexDirection: "column", lineHeight: 1.05 }}>
                <span style={{ ...wd.mono, fontSize: 11, fontWeight: 600, color: INK }}>{r.label}</span>
                <span style={{ ...wd.eyebrowSm, fontSize: 7.5, color: INK3 }}>{distVal(r.distMi, st.units).toFixed(2)}{distUnit(st.units)}</span>
              </div>
              {/* diverging pace bar */}
              <div style={{ position: "relative", height: 14 }}>
                <div style={{ position: "absolute", left: "50%", top: 0, bottom: 0, width: 1, background: INK3, opacity: 0.5 }} />
                <div style={{
                  position: "absolute", top: 4, height: 6, borderRadius: 1,
                  background: col, opacity: st.colorByZone ? 0.9 : faster ? 1 : 0.6,
                  ...(faster
                    ? { left: "50%", width: `${mag * 50}%` }
                    : { right: "50%", width: `${mag * 50}%` }),
                }} />
              </div>
              <span style={{ ...wd.mono, fontSize: 13, fontWeight: 600, color: isFast ? COR : INK, textAlign: "right" }}>{fmtPaceVal(r.paceSec, st.units, st.weatherAdjust)}</span>
              <span style={{ ...wd.mono, fontSize: 10.5, fontWeight: 600, color: faster ? "#2D8A4E" : INK3, textAlign: "right" }}>{delta === 0 ? "—" : `${faster ? "−" : "+"}${Math.abs(delta)}s`}</span>
              <span style={{ ...wd.mono, fontSize: 11, color: INK2, textAlign: "right" }}>{r.hr}</span>
              <span style={{ ...wd.mono, fontSize: 11, color: INK3, textAlign: "right" }}>{r.cad}</span>
            </div>
            {/* rest interstitial */}
            {r.rest && (
              <div style={{ display: "flex", alignItems: "center", gap: 7, padding: "3px 0 6px 18px", borderBottom: `1px solid ${RULE}`, marginBottom: 1 }}>
                <span style={{ flex: "0 0 auto", width: 18, height: 1, background: INK3, opacity: 0.4 }} />
                <span style={{ ...wd.eyebrowSm, fontSize: 8, color: INK3 }}>REST {r.rest}s</span>
                <span style={{ ...wd.eyebrowSm, fontSize: 8, color: INK3 }}>· JOG</span>
                {rest && <span style={{ ...wd.eyebrowSm, fontSize: 8, color: "#2D8A4E" }}>· HR −{rest.drop} → {rest.end}</span>}
              </div>
            )}
            {!r.rest && idx === REP_PLAN.length - 1 && <div style={{ borderBottom: `1px solid ${RULE}` }} />}
          </React.Fragment>
        );
      })}
      {/* totals footer */}
      <div style={{ display: "grid", gridTemplateColumns: SPLIT_COLS, gap: 8, alignItems: "center", padding: "9px 0 2px" }}>
        <span />
        <span style={{ ...wd.eyebrowSm, color: INK }}>ALL</span>
        <span style={{ ...wd.eyebrowSm, color: INK3 }}>{distVal(totDist, st.units).toFixed(2)}{distUnit(st.units)} WORK · {REP_PLAN.length} REPS</span>
        <span style={{ ...wd.mono, fontSize: 13, fontWeight: 600, color: COR, textAlign: "right" }}>{fmtPaceVal(target, st.units, st.weatherAdjust)}</span>
        <span style={{ ...wd.eyebrowSm, fontSize: 8, color: INK3, textAlign: "right" }}>AVG</span>
        <span style={{ ...wd.mono, fontSize: 11, color: INK2, textAlign: "right" }}>{avgHr}</span>
        <span style={{ ...wd.mono, fontSize: 11, color: INK3, textAlign: "right" }}>{avgCad}</span>
      </div>
    </div>
  );
}

/* ─── 9 · COMPARISON — recent same-type sessions ────────────────────── */
function ComparisonChart({ height = 150 }) {
  const st = wdStore.use();
  const set = COMPARE[st.comparison];
  const W = 340, H = height;
  const PAD_L = 34, PAD_R = 12, PAD_T = 16, PAD_B = 30;
  const plotW = W - PAD_L - PAD_R, plotH = H - PAD_T - PAD_B;
  const paces = set.series.map((s) => s.paceSec);
  const pmin = Math.min(...paces) - 6, pmax = Math.max(...paces) + 6;
  const n = set.series.length;
  const x = (i) => PAD_L + (n === 1 ? plotW / 2 : (i / (n - 1)) * plotW);
  const y = (p) => PAD_T + ((p - pmin) / (pmax - pmin)) * plotH; // faster (smaller) = higher
  const path = set.series.map((s, i) => `${i === 0 ? "M" : "L"} ${x(i).toFixed(1)} ${y(s.paceSec).toFixed(1)}`).join(" ");
  return (
    <svg viewBox={`0 0 ${W} ${H}`} style={{ width: "100%", height, display: "block" }}>
      <text x={PAD_L} y={9} fontFamily="var(--font-mono)" fontSize="8" fill={INK3} letterSpacing="0.1em">FASTER ↑ · AVG WORK PACE {paceUnit(st.units)}</text>
      <line x1={PAD_L} x2={PAD_L + plotW} y1={PAD_T + plotH} y2={PAD_T + plotH} stroke={RULE} strokeWidth="0.5" />
      <path d={path} fill="none" stroke={INK3} strokeWidth="1.2" strokeLinejoin="round" />
      {set.series.map((s, i) => (
        <g key={i}>
          <circle cx={x(i)} cy={y(s.paceSec)} r={s.this ? 4.5 : 3} fill={s.this ? COR : "var(--paper)"} stroke={s.this ? COR : INK2} strokeWidth="1.3" />
          {s.this && (
            <text x={x(i)} y={y(s.paceSec) - 9} textAnchor="middle" fontFamily="var(--font-mono)" fontSize="9" fontWeight="600" fill={COR}>
              {fmtPaceVal(s.paceSec, st.units, st.weatherAdjust)}
            </text>
          )}
          <text x={x(i)} y={H - 16} textAnchor="middle" fontFamily="var(--font-mono)" fontSize="7" fill={s.this ? COR : INK3}>{s.d.replace("Best · ", "")}</text>
        </g>
      ))}
      <text x={PAD_L} y={H - 3} fontFamily="var(--font-mono)" fontSize="7.5" fill={INK3} letterSpacing="0.06em" fontStyle="italic">{set.sub}</text>
    </svg>
  );
}

/* delta chips vs recent average */
function DeltaChips() {
  const st = wdStore.use();
  const items = [
    { l: "PACE", now: WK.avgWorkPaceSec, then: RECENT_AVG.paceSec, fmt: (v) => fmtPaceVal(v, st.units, false), inv: true },
    { l: "AVG HR", now: WK.avgHr, then: RECENT_AVG.hr, fmt: (v) => Math.round(v), inv: false },
    { l: "CADENCE", now: WK.avgCadence, then: RECENT_AVG.cad, fmt: (v) => Math.round(v), inv: false },
  ];
  return (
    <div style={{ display: "grid", gridTemplateColumns: "repeat(3,1fr)", gap: 8, marginTop: 8 }}>
      {items.map((it) => {
        const delta = it.now - it.then;
        const better = it.inv ? delta < 0 : delta > 0;
        const pct = (delta / it.then) * 100;
        return (
          <div key={it.l} style={{ border: `1px solid ${RULE}`, padding: "8px 10px" }}>
            <span style={wd.eyebrowSm}>{it.l}</span>
            <div style={{ ...wd.mono, fontSize: 15, fontWeight: 600, color: INK, marginTop: 3 }}>{it.fmt(it.now)}</div>
            <span style={{ ...wd.eyebrowSm, fontSize: 8, color: better ? "#2D8A4E" : INK3 }}>
              {pct > 0 ? "+" : ""}{pct.toFixed(1)}% vs avg
            </span>
          </div>
        );
      })}
    </div>
  );
}

/* ─── 10 · ROUTE MAP — line colored by pace, rep markers ────────────── */
function RouteMap({ height = 150 }) {
  const st = wdStore.use();
  const W = 340, H = height;
  // pseudo route from latlng-ish synthesized loop
  const pts = [];
  const N = STREAM.time.length;
  for (let i = 0; i < N; i += 4) {
    const t = STREAM.time[i] / STREAM.totalSec;
    const ang = t * Math.PI * 2.3;
    const r = 0.5 + 0.32 * Math.sin(ang * 1.7) + 0.1 * Math.cos(ang * 3.1);
    pts.push({
      x: 28 + (0.5 + r * Math.cos(ang) * 0.62) * (W - 56),
      y: 14 + (0.5 + r * Math.sin(ang) * 0.6) * (H - 40),
      hr: STREAM.hr[i], pace: STREAM.pace[i], sec: STREAM.time[i],
    });
  }
  const segCol = (p) => {
    if (st.colorByZone) return zoneOf(p.hr).color;
    const fast = p.pace < 360;
    return fast ? COR : INK3;
  };
  // rep start markers
  const repStarts = STREAM.repBands.filter((b) => b.kind === "rep").map((b) => {
    const near = pts.reduce((a, c) => (Math.abs(c.sec - b.startSec) < Math.abs(a.sec - b.startSec) ? c : a), pts[0]);
    return { ...near, rep: b.rep };
  });
  return (
    <div style={{ position: "relative", width: "100%", height, border: `1px solid ${RULE}`, background: "var(--paper-elevated)", overflow: "hidden" }}>
      <svg viewBox={`0 0 ${W} ${H}`} style={{ width: "100%", height: "100%", display: "block" }}>
        {/* faint paper grid */}
        {[0.25, 0.5, 0.75].map((f) => <line key={`h${f}`} x1="0" x2={W} y1={f * H} y2={f * H} stroke={RULE} strokeWidth="0.4" />)}
        {[0.25, 0.5, 0.75].map((f) => <line key={`v${f}`} x1={f * W} x2={f * W} y1="0" y2={H} stroke={RULE} strokeWidth="0.4" />)}
        {pts.slice(1).map((p, i) => (
          <line key={i} x1={pts[i].x} y1={pts[i].y} x2={p.x} y2={p.y} stroke={segCol(p)} strokeWidth="2.4" strokeLinecap="round" opacity="0.9" />
        ))}
        {repStarts.map((p) => (
          <g key={p.rep}>
            <circle cx={p.x} cy={p.y} r="6.5" fill="var(--paper)" stroke={INK} strokeWidth="1.2" />
            <text x={p.x} y={p.y + 3} textAnchor="middle" fontFamily="var(--font-mono)" fontSize="8" fontWeight="600" fill={INK}>{p.rep}</text>
          </g>
        ))}
        <circle cx={pts[0].x} cy={pts[0].y} r="3.5" fill={INK} />
        <circle cx={pts[pts.length - 1].x} cy={pts[pts.length - 1].y} r="3.5" fill={COR} />
      </svg>
      <div style={{ position: "absolute", top: 8, left: 10, ...wd.eyebrowSm }}>{WK.place}</div>
      <div style={{ position: "absolute", bottom: 8, left: 10, ...wd.eyebrowSm }}>
        {st.colorByZone ? "COLORED BY HR ZONE" : "CORAL = WORK · GRAY = EASY"} · ① REP STARTS
      </div>
    </div>
  );
}

Object.assign(window, {
  RepChart, HRZoneTimeline, PaceTrace, CadenceStrip, ElevGradeProfile,
  RepRecovery, TimeInZoneBar, RepTable, ComparisonChart, DeltaChips, RouteMap,
});

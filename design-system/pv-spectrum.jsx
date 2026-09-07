/* global React, window */
/* ============================================================
   DIRECTION A · SPECTRUM (refined density ridgeline)
   The original concept, fixed: smooth zone gradient, an honest
   anchor rail, a draggable scrubber, an 80/20 + trend footer.
   ============================================================ */
(function () {
  "use strict";
  const { useMemo } = React;
  const PV = window.PV;
  const { usePointerX, Sparkline } = window.PVUI;

  const W = 358, LABEL = 38, PLOT = 132, AX = 22;
  const TOP = LABEL, BASE = LABEL + PLOT, H = LABEL + PLOT + AX;

  function gradientStops(scale) {
    return PV.ZONES
      .filter((z) => z.lo < scale.paceSlow && z.hi > scale.paceFast)
      .map((z) => {
        const hi = Math.min(z.hi, scale.paceSlow);
        const lo = Math.max(z.lo, scale.paceFast);
        const center = Math.min(Math.max((hi + lo) / 2, scale.paceFast), scale.paceSlow);
        return { off: scale.xFromPace(center, W) / W, color: z.color };
      })
      .sort((a, b) => a.off - b.off);
  }

  function anchorRows(scale) {
    const items = PV.ANCHORS
      .filter((a) => a.paceSeconds <= scale.paceSlow && a.paceSeconds >= scale.paceFast)
      .map((a) => ({ ...a, x: scale.xFromPace(a.paceSeconds, W) }))
      .sort((a, b) => a.x - b.x);
    let lastX = [-99, -99];
    return items.map((a) => {
      let row = 0;
      if (Math.abs(a.x - lastX[0]) < 46) row = Math.abs(a.x - lastX[1]) < 46 ? 0 : 1;
      lastX[row] = a.x;
      return { ...a, row };
    });
  }

  function axisTicks(scale) {
    const out = [];
    for (let p = Math.ceil(scale.paceFast / 30) * 30; p <= scale.paceSlow; p += 30) {
      if (p % 60 === 0) out.push(p);
    }
    return out;
  }

  function SpectrumBody({ mode }) {
    const scrub = usePointerX();
    const scale = useMemo(() => {
      const a = PV.AXIS[mode];
      return Object.assign(PV.makeScale(a.slow, a.fast), { bw: a.bw });
    }, [mode]);
    const samples = useMemo(() => PV.samplesFor(mode), [mode]);

    const curve = useMemo(() => {
      const dens = PV.kde(samples, scale.bw);
      const N = 140, ys = [], ps = [];
      for (let i = 0; i <= N; i++) {
        const x = (i / N) * W;
        const p = scale.paceFromX(x, W);
        ps.push(p); ys.push(dens(p));
      }
      const max = Math.max(...ys) || 1;
      const pts = ys.map((y, i) => [(i / N) * W, BASE - (y / max) * PLOT * 0.82]);
      const top = pts.map((p, i) => (i ? "L" : "M") + p[0].toFixed(1) + " " + p[1].toFixed(1)).join(" ");
      const area = "M0 " + BASE + " " + top.replace(/^M/, "L") + " L" + W + " " + BASE + " Z";
      return { top, area };
    }, [samples, scale]);

    const agg = useMemo(() => PV.aggregate(PV.WORKOUTS), []);
    const trend = useMemo(() => PV.weeklyTrend(PV.WORKOUTS), []);
    const easyDelta = Math.round((trend[0].easy || 0) - (trend[8].easy || 0));

    // scrubber readout
    const read = useMemo(() => {
      if (scrub.t == null) return null;
      const pace = scale.paceFromX(scrub.t * W, W);
      const easier = samples.reduce((s, w) => s + (w.paceSeconds >= pace ? w.miles : 0), 0);
      const tot = samples.reduce((s, w) => s + w.miles, 0) || 1;
      return { pace, x: scrub.t * W, zone: PV.zoneOf(pace), pct: Math.round((easier / tot) * 100) };
    }, [scrub.t, scale, samples]);

    const stops = gradientStops(scale);
    const anchors = anchorRows(scale);
    const ticks = axisTicks(scale);
    const gid = "pvgradA-" + mode;

    return (
      <React.Fragment>
        <div style={{ padding: "8px 16px 0", position: "relative" }}>
          <svg viewBox={`0 0 ${W} ${H}`} style={{ width: "100%", display: "block", touchAction: "none", cursor: "crosshair" }}
            ref={scrub.ref} {...scrub.bind}>
            <defs>
              <linearGradient id={gid} x1="0" y1="0" x2="1" y2="0">
                {stops.map((s, i) => <stop key={i} offset={s.off} stopColor={s.color} stopOpacity="0.92" />)}
              </linearGradient>
              <linearGradient id={gid + "-v"} x1="0" y1="0" x2="0" y2="1">
                <stop offset="0" stopColor="#000" stopOpacity="0.06" />
                <stop offset="1" stopColor="#000" stopOpacity="0" />
              </linearGradient>
            </defs>

            {/* anchor hairlines */}
            {anchors.map((a) => (
              <line key={a.id} x1={a.x} x2={a.x} y1={TOP - 2} y2={BASE}
                stroke="var(--ink)" strokeOpacity="0.16" strokeWidth="1" strokeDasharray="2 3" />
            ))}

            {/* density */}
            <path d={curve.area} fill={`url(#${gid})`} />
            <path d={curve.area} fill={`url(#${gid}-v)`} />
            <path d={curve.top} fill="none" stroke="var(--ink)" strokeWidth="1.4" strokeLinejoin="round" />
            <line x1="0" x2={W} y1={BASE} y2={BASE} stroke="var(--rule)" strokeWidth="1" />

            {/* anchor labels */}
            {anchors.map((a) => {
              const z = PV.zoneOf(a.paceSeconds);
              const y = a.row === 0 ? 12 : 27;
              return (
                <g key={a.id} transform={`translate(${a.x}, 0)`} textAnchor="middle">
                  <text y={y} style={{ fontFamily: "var(--font-mono)", fontSize: 9, fontWeight: 600, letterSpacing: ".5px" }} fill={z.ink}>{a.label}</text>
                  <text y={y + 10} style={{ fontFamily: "var(--font-mono)", fontSize: 8.5 }} fill="var(--ink-2)">{PV.fmtPace(a.paceSeconds)}</text>
                  <rect x={-1} y={a.row === 0 ? TOP - 6 : TOP - 6} width="2" height="4" fill={z.ink} />
                </g>
              );
            })}

            {/* axis ticks */}
            {ticks.map((p) => (
              <text key={p} x={scale.xFromPace(p, W)} y={H - 5} textAnchor="middle"
                style={{ fontFamily: "var(--font-mono)", fontSize: 9 }} fill="var(--ink-3)">{PV.fmtPace(p)}</text>
            ))}

            {/* scrubber */}
            {read && (
              <g>
                <line x1={read.x} x2={read.x} y1={TOP - 4} y2={BASE} stroke="var(--coral)" strokeWidth="1.2" />
                <circle cx={read.x} cy={BASE} r="3" fill="var(--coral)" />
              </g>
            )}
          </svg>

          {/* scrubber readout */}
          <div style={{ height: 34, marginTop: 2, display: "flex", justifyContent: "center" }}>
            {read ? (
              <div style={{ textAlign: "center" }}>
                <span style={{ fontFamily: "var(--font-mono)", fontSize: 14, fontWeight: 600, color: "var(--ink)" }}>{PV.fmtPace(read.pace)}</span>
                <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: read.zone.ink, marginLeft: 8, letterSpacing: ".5px" }}>{read.zone.name.toUpperCase()}</span>
                <div style={{ fontFamily: "var(--font-body)", fontSize: 11.5, color: "var(--ink-2)", marginTop: 1 }}>
                  {read.pct}% of miles run easier than this
                </div>
              </div>
            ) : (
              <div style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 12, color: "var(--ink-3)", alignSelf: "center" }}>
                Drag across the curve to read any pace
              </div>
            )}
          </div>
        </div>

        {/* footer: 80/20 + trend */}
        <div style={{ padding: "6px 22px 4px", display: "flex", gap: 18, alignItems: "center" }}>
          <div style={{ flex: 1 }}>
            <div style={{ display: "flex", height: 8, borderRadius: 4, overflow: "hidden" }}>
              <span style={{ width: (100 - agg.qualityPct) + "%", background: "var(--mood-positive)" }} />
              <span style={{ width: agg.qualityPct + "%", background: "var(--coral)" }} />
            </div>
            <div style={{ display: "flex", justifyContent: "space-between", marginTop: 5, fontFamily: "var(--font-mono)", fontSize: 9.5, letterSpacing: ".4px" }}>
              <span style={{ color: "var(--mood-positive)" }}>AEROBIC {Math.round(100 - agg.qualityPct)}%</span>
              <span style={{ color: "var(--ink-3)" }}>80 / 20 TARGET</span>
              <span style={{ color: "var(--coral)" }}>{Math.round(agg.qualityPct)}% QUALITY</span>
            </div>
          </div>
          <div style={{ borderLeft: "1px solid var(--rule)", paddingLeft: 16, textAlign: "right" }}>
            <div style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-2)", letterSpacing: ".6px" }}>EASY PACE</div>
            <div style={{ display: "flex", alignItems: "center", gap: 6, marginTop: 3 }}>
              <Sparkline values={trend.map((t) => t.easy)} color="var(--mood-positive)" />
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 12, fontWeight: 600, color: "var(--mood-positive)" }}>−{easyDelta}s</span>
            </div>
          </div>
        </div>
      </React.Fragment>
    );
  }

  window.SpectrumBody = SpectrumBody;
})();

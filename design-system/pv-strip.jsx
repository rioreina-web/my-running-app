/* global React, window */
/* ============================================================
   DIRECTION C · MILE STRIP (beeswarm)
   Every run is one dot on the pace axis — x = avg pace,
   size = miles, color = zone, fade = how early in the block.
   No smoothing: you see exactly where the miles landed.
   Drag to inspect any run.
   ============================================================ */
(function () {
  "use strict";
  const { useMemo } = React;
  const PV = window.PV;
  const { usePointerX } = window.PVUI;

  const W = 358, RIDGE = 30, GAP = 6, PLOT = 132, AX = 22;
  const PTOP = RIDGE + GAP, PBASE = RIDGE + GAP + PLOT, H = PBASE + AX;
  const radius = (mi) => 3.4 + Math.sqrt(mi) * 1.25;

  function beeswarm(samples, scale) {
    const cy = PTOP + PLOT * 0.52;
    const pts = samples.map((w) => ({
      w, x: scale.xFromPace(w.paceSeconds, W), r: radius(w.miles),
      zone: PV.zoneOf(w.paceSeconds),
    })).sort((a, b) => a.x - b.x);
    const placed = [];
    pts.forEach((p) => {
      let y = cy, k = 0;
      const hit = (yy) => placed.some((q) => Math.hypot(p.x - q.x, yy - q.y) < p.r + q.r + 1.5);
      while (hit(y) && k < 80) {
        k++;
        const mag = Math.ceil(k / 2) * (p.r * 0.85);
        y = cy + (k % 2 === 0 ? -mag : mag);
      }
      y = Math.min(Math.max(y, PTOP + p.r), PBASE - p.r);
      placed.push({ ...p, y });
    });
    return placed;
  }

  function ridgePath(samples, scale, bw) {
    const dens = PV.kde(samples, bw);
    const N = 120, ys = [];
    for (let i = 0; i <= N; i++) ys.push(dens(scale.paceFromX((i / N) * W, W)));
    const max = Math.max(...ys) || 1;
    return ys.map((y, i) => ((i ? "L" : "M") + ((i / N) * W).toFixed(1) + " " + (RIDGE - (y / max) * (RIDGE - 3)).toFixed(1))).join(" ");
  }

  function StripBody({ mode }) {
    const scrub = usePointerX();
    const scale = useMemo(() => {
      const a = PV.AXIS[mode];
      return Object.assign(PV.makeScale(a.slow, a.fast), { bw: a.bw });
    }, [mode]);
    const samples = useMemo(() => PV.samplesFor(mode), [mode]);
    const dots = useMemo(() => beeswarm(samples, scale), [samples, scale]);
    const ridge = useMemo(() => ridgePath(samples, scale, scale.bw), [samples, scale]);

    const anchors = useMemo(() => PV.ANCHORS
      .filter((a) => a.paceSeconds <= scale.paceSlow && a.paceSeconds >= scale.paceFast)
      .map((a) => ({ ...a, x: scale.xFromPace(a.paceSeconds, W), zone: PV.zoneOf(a.paceSeconds) })), [scale]);

    const ticks = useMemo(() => {
      const out = [];
      for (let p = Math.ceil(scale.paceFast / 60) * 60; p <= scale.paceSlow; p += 60) out.push(p);
      return out;
    }, [scale]);

    // nearest dot to pointer
    const active = useMemo(() => {
      if (scrub.t == null || !dots.length) return null;
      const px = scrub.t * W;
      let best = null, bd = 1e9;
      dots.forEach((d) => { const dist = Math.abs(d.x - px); if (dist < bd) { bd = dist; best = d; } });
      return bd < 26 ? best : null;
    }, [scrub.t, dots]);

    return (
      <React.Fragment>
        <div style={{ padding: "8px 16px 0", position: "relative" }}>
          <svg viewBox={`0 0 ${W} ${H}`} style={{ width: "100%", display: "block", touchAction: "none", cursor: "crosshair" }}
            ref={scrub.ref} {...scrub.bind}>
            {/* anchor hairlines */}
            {anchors.map((a) => (
              <line key={a.id} x1={a.x} x2={a.x} y1={PTOP - 4} y2={PBASE}
                stroke="var(--ink)" strokeOpacity="0.14" strokeWidth="1" strokeDasharray="2 3" />
            ))}

            {/* marginal ridge for context */}
            <path d={ridge} fill="none" stroke="var(--ink-3)" strokeWidth="1" strokeLinejoin="round" />

            {/* dots */}
            {dots.map((d) => {
              const recency = 0.4 + (d.w.week / 9) * 0.6;
              const isOn = active && active.w.id === d.w.id;
              return (
                <circle key={d.w.id} cx={d.x} cy={d.y} r={d.r}
                  fill={d.zone.color} fillOpacity={isOn ? 1 : recency}
                  stroke={isOn ? "var(--ink)" : "#fff"} strokeWidth={isOn ? 1.4 : 0.6} strokeOpacity={isOn ? 1 : 0.5} />
              );
            })}

            {/* scrubber guide */}
            {scrub.t != null && (
              <line x1={scrub.t * W} x2={scrub.t * W} y1={PTOP - 4} y2={PBASE}
                stroke="var(--coral)" strokeWidth="1" strokeOpacity="0.5" />
            )}

            {/* anchor labels (bottom, subtle) */}
            {anchors.map((a) => (
              <g key={a.id} transform={`translate(${a.x}, ${PBASE + 8})`} textAnchor="middle">
                <text style={{ fontFamily: "var(--font-mono)", fontSize: 8.5, fontWeight: 600, letterSpacing: ".4px" }} fill={a.zone.ink}>{a.label}</text>
              </g>
            ))}
            {ticks.map((p) => (
              <text key={p} x={scale.xFromPace(p, W)} y={H - 4} textAnchor="middle"
                style={{ fontFamily: "var(--font-mono)", fontSize: 8.5 }} fill="var(--ink-3)">{PV.fmtPace(p)}</text>
            ))}
          </svg>

          {/* readout */}
          <div style={{ height: 36, marginTop: 2, display: "flex", justifyContent: "center", alignItems: "center" }}>
            {active ? (
              <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
                <span style={{ width: 10, height: 10, borderRadius: 2, background: active.zone.color }} />
                <div>
                  <span style={{ fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 15 }}>{active.w.type}</span>
                  <span style={{ fontFamily: "var(--font-mono)", fontSize: 10.5, color: "var(--ink-3)", marginLeft: 8 }}>WK {active.w.week} · {active.w.day.toUpperCase()}</span>
                </div>
                <span style={{ fontFamily: "var(--font-mono)", fontSize: 13, fontWeight: 600, color: "var(--ink)" }}>{active.w.miles} mi</span>
                <span style={{ fontFamily: "var(--font-mono)", fontSize: 13, fontWeight: 600, color: active.zone.ink }}>{PV.fmtPace(active.w.paceSeconds)}</span>
              </div>
            ) : (
              <div style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 12, color: "var(--ink-3)" }}>
                Drag across the runs to inspect any one
              </div>
            )}
          </div>
        </div>

        {/* footer: recency legend + count */}
        <div style={{ padding: "4px 22px 6px", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-2)", letterSpacing: ".5px" }}>WK 1</span>
            <span style={{ width: 56, height: 7, borderRadius: 4, background: "linear-gradient(90deg, rgba(74,158,107,.4), rgba(74,158,107,1))" }} />
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-2)", letterSpacing: ".5px" }}>WK 9</span>
          </div>
          <span style={{ fontFamily: "var(--font-mono)", fontSize: 9.5, color: "var(--ink-3)", letterSpacing: ".4px" }}>
            {dots.length} RUNS · FADE = HOW RECENT
          </span>
        </div>
      </React.Fragment>
    );
  }

  window.StripBody = StripBody;
})();

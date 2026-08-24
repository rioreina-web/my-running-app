/* global React, window */
/* ============================================================
   DIRECTION E · ZONE RING (the block as one wheel)
   A donut of zone shares — slow zones sweep from the top
   clockwise into the fast ones. The center holds the headline:
   total miles, or the 80/20 aerobic-vs-quality split. Tap a
   segment to isolate a zone in the hub.
   ============================================================ */
(function () {
  "use strict";
  const { useState, useMemo } = React;
  const PV = window.PV;

  const SIZE = 230, CX = SIZE / 2, CY = SIZE / 2;
  const R = 92, SW = 30, GAP = 2.5; // ring radius, stroke width, gap in degrees

  function polar(r, deg) {
    const a = (deg - 90) * (Math.PI / 180);
    return [CX + r * Math.cos(a), CY + r * Math.sin(a)];
  }
  function arcPath(r, a0, a1) {
    const [x0, y0] = polar(r, a0);
    const [x1, y1] = polar(r, a1);
    const large = a1 - a0 > 180 ? 1 : 0;
    return `M ${x0.toFixed(2)} ${y0.toFixed(2)} A ${r} ${r} 0 ${large} 1 ${x1.toFixed(2)} ${y1.toFixed(2)}`;
  }

  function RingBody({ mode }) {
    const [sel, setSel] = useState(null);
    const qualityOnly = mode === "workouts";

    const agg = useMemo(() => PV.aggregate(PV.WORKOUTS), []);
    const data = useMemo(() => {
      let rows = agg.rows.filter((r) => r.miles > 0);
      if (qualityOnly) {
        rows = rows.filter((r) => PV.QUALITY_IDS.includes(r.zone.id));
        const tot = rows.reduce((s, r) => s + r.miles, 0) || 1;
        rows = rows.map((r) => ({ ...r, pct: (r.miles / tot) * 100 }));
      }
      // slow → fast around the wheel
      return rows;
    }, [agg, qualityOnly]);

    const totalMiles = qualityOnly ? agg.qualityMiles : agg.total;
    const aerobicPct = 100 - agg.qualityPct;

    // build segments (clockwise from top)
    const segs = useMemo(() => {
      let cursor = 0;
      return data.map((r) => {
        const sweep = (r.pct / 100) * 360;
        const a0 = cursor + GAP / 2;
        const a1 = cursor + sweep - GAP / 2;
        cursor += sweep;
        return { ...r, a0: Math.max(a0, cursor - sweep), a1, mid: cursor - sweep / 2 };
      });
    }, [data]);

    const activeRow = sel ? data.find((r) => r.zone.id === sel) : null;

    return (
      <React.Fragment>
        <div style={{ display: "flex", justifyContent: "center", padding: "6px 16px 0" }}>
          <svg viewBox={`0 0 ${SIZE} ${SIZE}`} width="230" height="230" style={{ display: "block", overflow: "visible" }}>
            {/* track */}
            <circle cx={CX} cy={CY} r={R} fill="none" stroke="var(--paper-deep)" strokeWidth={SW} />
            {/* segments */}
            {segs.map((s) => {
              const dim = sel && sel !== s.zone.id;
              return (
                <path key={s.zone.id} d={arcPath(R, s.a0, s.a1)} fill="none"
                  stroke={s.zone.color} strokeWidth={SW} strokeLinecap="butt"
                  opacity={dim ? 0.3 : 1}
                  style={{ cursor: "pointer", transition: "opacity .18s" }}
                  onClick={() => setSel(sel === s.zone.id ? null : s.zone.id)} />
              );
            })}
            {/* tick labels on outer edge for the larger segments */}
            {segs.filter((s) => s.pct >= 7).map((s) => {
              const [lx, ly] = polar(R + SW / 2 + 11, s.mid);
              return (
                <text key={s.zone.id} x={lx} y={ly} textAnchor="middle" dominantBaseline="middle"
                  style={{ fontFamily: "var(--font-mono)", fontSize: 8.5, fontWeight: 600, letterSpacing: ".3px" }}
                  fill={sel && sel !== s.zone.id ? "var(--ink-3)" : s.zone.ink}>
                  {s.zone.short}
                </text>
              );
            })}

            {/* hub */}
            {activeRow ? (
              <g textAnchor="middle">
                <text y={CY - 14} style={{ fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 600, letterSpacing: ".6px" }} fill={activeRow.zone.ink}>
                  {activeRow.zone.name.toUpperCase()}
                </text>
                <text y={CY + 16} style={{ fontFamily: "var(--font-mono)", fontSize: 34, fontWeight: 600 }} fill="var(--ink)">
                  {Math.round(activeRow.pct)}<tspan style={{ fontSize: 15 }} dy="0">%</tspan>
                </text>
                <text y={CY + 34} style={{ fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 500 }} fill="var(--ink-2)">
                  {activeRow.miles.toFixed(0)} MI · {activeRow.runs} RUNS
                </text>
              </g>
            ) : (
              <g textAnchor="middle">
                <text y={CY - 20} style={{ fontFamily: "var(--font-mono)", fontSize: 9.5, fontWeight: 500, letterSpacing: ".8px" }} fill="var(--ink-2)">
                  {qualityOnly ? "QUALITY MILES" : "BLOCK TOTAL"}
                </text>
                <text y={CY + 14} style={{ fontFamily: "var(--font-mono)", fontSize: 40, fontWeight: 600 }} fill="var(--ink)">
                  {Math.round(totalMiles)}
                </text>
                <text y={CY + 34} style={{ fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 500, letterSpacing: ".4px" }} fill="var(--coral)">
                  {qualityOnly ? "ALL FAST" : Math.round(aerobicPct) + " / " + Math.round(agg.qualityPct)}
                </text>
              </g>
            )}
          </svg>
        </div>

        {/* legend grid */}
        <div style={{ padding: "12px 22px 0", display: "grid", gridTemplateColumns: "1fr 1fr", gap: "8px 18px" }}>
          {data.slice().reverse().map((r) => {
            const dim = sel && sel !== r.zone.id;
            return (
              <div key={r.zone.id} onClick={() => setSel(sel === r.zone.id ? null : r.zone.id)}
                style={{ display: "flex", alignItems: "center", gap: 8, cursor: "pointer", opacity: dim ? 0.42 : 1, transition: "opacity .18s" }}>
                <span style={{ width: 9, height: 9, borderRadius: 2, background: r.zone.color, flexShrink: 0 }} />
                <span style={{ fontFamily: "var(--font-display)", fontWeight: 600, fontSize: 14, color: "var(--ink)", flex: 1 }}>{r.zone.name}</span>
                <span style={{ fontFamily: "var(--font-mono)", fontSize: 12, fontWeight: 600, color: "var(--ink)", fontVariantNumeric: "tabular-nums" }}>{Math.round(r.pct)}%</span>
              </div>
            );
          })}
        </div>

        {/* footer insight */}
        <div style={{ padding: "12px 22px 4px" }}>
          <p style={{ fontFamily: "var(--font-body)", fontSize: 12.5, lineHeight: 1.45, color: "var(--ink-2)", margin: 0 }}>
            {qualityOnly
              ? <React.Fragment>The wheel of <span style={{ color: "var(--coral)", fontWeight: 700 }}>quality</span> only — where the hard miles actually went.</React.Fragment>
              : <React.Fragment>Aerobic zones fill <span style={{ color: "var(--mood-positive)", fontWeight: 700 }}>{Math.round(aerobicPct)}%</span> of the wheel — the base that carries the {Math.round(agg.qualityPct)}% of sharpening on top.</React.Fragment>}
          </p>
        </div>
      </React.Fragment>
    );
  }

  window.RingBody = RingBody;
})();

/* global React, window */
/* ============================================================
   DIRECTION D · WEEKLY BUILD (stacked columns over the block)
   The only view with TIME on the x-axis. Nine weeks, each a
   stacked column of miles by zone — aerobic base at the bottom,
   quality stacked on top. You read the progression: rising
   volume, the week-6 deload, intensity sharpening late.
   Hover a week to read it.
   ============================================================ */
(function () {
  "use strict";
  const { useState, useMemo } = React;
  const PV = window.PV;

  const W = 358, LABEL = 14, PLOT = 150, AX = 20;
  const TOP = LABEL, BASE = LABEL + PLOT, H = LABEL + PLOT + AX;
  const PADX = 8;

  function weeklyStacks(qualityOnly) {
    const zones = PV.ZONES.filter((z) => (qualityOnly ? PV.QUALITY_IDS.includes(z.id) : true));
    const weeks = [];
    for (let w = 1; w <= 9; w++) {
      const runs = PV.WORKOUTS.filter((x) => x.week === w);
      const by = {};
      PV.ZONES.forEach((z) => (by[z.id] = 0));
      runs.forEach((r) => { const z = PV.zoneOf(r.paceSeconds); by[z.id] += r.miles; });
      const total = zones.reduce((s, z) => s + by[z.id], 0);
      const quality = PV.QUALITY_IDS.reduce((s, id) => s + by[id], 0);
      weeks.push({ week: w, by, total, quality });
    }
    return { weeks, zones };
  }

  function WeeklyBody({ mode }) {
    const [hover, setHover] = useState(null);
    const qualityOnly = mode === "workouts";

    const { weeks, zones } = useMemo(() => weeklyStacks(qualityOnly), [qualityOnly]);
    const maxMi = useMemo(() => Math.max(...weeks.map((w) => w.total)) || 1, [weeks]);
    // a clean rounded ceiling for the gridline
    const ceil = Math.ceil(maxMi / 10) * 10;

    const colGap = 9;
    const colW = (W - PADX * 2 - colGap * 8) / 9;
    const xOf = (i) => PADX + i * (colW + colGap);
    const yOf = (mi) => BASE - (mi / ceil) * PLOT;

    const avg = weeks.reduce((s, w) => s + w.total, 0) / 9;
    const peak = weeks.reduce((a, b) => (b.total > a.total ? b : a), weeks[0]);
    const active = hover != null ? weeks[hover] : null;

    return (
      <React.Fragment>
        <div style={{ padding: "10px 16px 0", position: "relative" }}>
          <svg viewBox={`0 0 ${W} ${H}`} style={{ width: "100%", display: "block", touchAction: "none" }}>
            {/* y gridlines */}
            {[0.5, 1].map((f) => (
              <g key={f}>
                <line x1={PADX} x2={W - PADX} y1={yOf(ceil * f)} y2={yOf(ceil * f)}
                  stroke="var(--rule)" strokeWidth="1" />
                <text x={PADX} y={yOf(ceil * f) - 3}
                  style={{ fontFamily: "var(--font-mono)", fontSize: 8 }} fill="var(--ink-3)">
                  {Math.round(ceil * f)}
                </text>
              </g>
            ))}
            {/* avg dashed line */}
            <line x1={PADX} x2={W - PADX} y1={yOf(avg)} y2={yOf(avg)}
              stroke="var(--coral)" strokeWidth="1" strokeDasharray="2 3" strokeOpacity="0.7" />
            <text x={W - PADX} y={yOf(avg) - 3} textAnchor="end"
              style={{ fontFamily: "var(--font-mono)", fontSize: 8, letterSpacing: ".3px" }} fill="var(--coral)">
              AVG {Math.round(avg)}
            </text>

            {/* baseline */}
            <line x1={PADX} x2={W - PADX} y1={BASE} y2={BASE} stroke="var(--ink)" strokeOpacity="0.25" strokeWidth="1" />

            {/* columns */}
            {weeks.map((wk, i) => {
              let acc = 0;
              const dim = hover != null && hover !== i;
              return (
                <g key={wk.week}
                  onMouseEnter={() => setHover(i)} onMouseLeave={() => setHover(null)}
                  onTouchStart={() => setHover(i)}
                  style={{ cursor: "pointer" }}>
                  {/* hit area */}
                  <rect x={xOf(i) - colGap / 2} y={TOP} width={colW + colGap} height={PLOT} fill="transparent" />
                  {zones.map((z) => {
                    const mi = wk.by[z.id];
                    if (mi <= 0) return null;
                    const y0 = yOf(acc), y1 = yOf(acc + mi);
                    acc += mi;
                    return (
                      <rect key={z.id} x={xOf(i)} y={y1} width={colW} height={Math.max(y0 - y1, 0)}
                        fill={z.color} opacity={dim ? 0.32 : 1}
                        stroke="var(--paper)" strokeWidth="0.75" style={{ transition: "opacity .16s" }} />
                    );
                  })}
                  {/* week 6 deload marker */}
                  {wk.week === 6 && hover == null && (
                    <text x={xOf(i) + colW / 2} y={yOf(wk.total) - 5} textAnchor="middle"
                      style={{ fontFamily: "var(--font-mono)", fontSize: 7.5, letterSpacing: ".3px" }} fill="var(--ink-3)">
                      DELOAD
                    </text>
                  )}
                </g>
              );
            })}

            {/* week labels */}
            {weeks.map((wk, i) => (
              <text key={wk.week} x={xOf(i) + colW / 2} y={H - 6} textAnchor="middle"
                style={{ fontFamily: "var(--font-mono)", fontSize: 8.5, fontWeight: hover === i ? 700 : 400 }}
                fill={hover === i ? "var(--ink)" : "var(--ink-3)"}>
                {wk.week}
              </text>
            ))}
          </svg>

          {/* readout */}
          <div style={{ height: 36, marginTop: 2, display: "flex", justifyContent: "center", alignItems: "center" }}>
            {active ? (
              <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
                <span style={{ fontFamily: "var(--font-mono)", fontSize: 10.5, color: "var(--ink-3)", letterSpacing: ".5px" }}>WEEK {active.week}</span>
                <span style={{ fontFamily: "var(--font-mono)", fontSize: 15, fontWeight: 600, color: "var(--ink)" }}>{Math.round(active.total)} mi</span>
                <span style={{ fontFamily: "var(--font-mono)", fontSize: 12.5, fontWeight: 600, color: "var(--coral)" }}>
                  {active.total ? Math.round((active.quality / active.total) * 100) : 0}% quality
                </span>
              </div>
            ) : (
              <div style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 12, color: "var(--ink-3)" }}>
                Hover any week to read its mileage
              </div>
            )}
          </div>
        </div>

        {/* footer: zone legend + peak callout */}
        <div style={{ padding: "4px 22px 6px", display: "flex", alignItems: "center", justifyContent: "space-between", gap: 14 }}>
          <div style={{ display: "flex", flexWrap: "wrap", gap: "5px 12px" }}>
            {zones.slice().reverse().map((z) => (
              <span key={z.id} style={{ display: "flex", alignItems: "center", gap: 5 }}>
                <span style={{ width: 8, height: 8, borderRadius: 2, background: z.color }} />
                <span style={{ fontFamily: "var(--font-mono)", fontSize: 8.5, color: "var(--ink-2)", letterSpacing: ".3px" }}>{z.short}</span>
              </span>
            ))}
          </div>
          <div style={{ textAlign: "right", flexShrink: 0 }}>
            <div style={{ fontFamily: "var(--font-mono)", fontSize: 8.5, color: "var(--ink-2)", letterSpacing: ".5px" }}>PEAK WK {peak.week}</div>
            <div style={{ fontFamily: "var(--font-mono)", fontSize: 13, fontWeight: 600, color: "var(--ink)" }}>{Math.round(peak.total)} <span style={{ fontSize: 9, color: "var(--ink-2)", fontWeight: 400 }}>MI</span></div>
          </div>
        </div>
      </React.Fragment>
    );
  }

  window.WeeklyBody = WeeklyBody;
})();

// Direction B — Cockpit / Bar chart
// The week becomes a horizontal mileage bar chart. The training
// rhythm is visible at a glance. Coach sees: where the quality is,
// where the volume sits, how the week peaks.

const PlanBuilderB = () => {
  // Compute heights for the bars (max 20 mi from PLAN data)
  const maxMiles = 20;
  return (
    <div className="app-shell">
      <Sidebar />
      <main style={{ padding: "24px 36px 36px 36px", overflow: "auto", display: "flex", flexDirection: "column", gap: 0 }}>

        {/* Top toolbar — compact */}
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", paddingBottom: 18, borderBottom: "1px solid var(--rule)" }}>
          <div style={{ display: "flex", alignItems: "baseline", gap: 14 }}>
            <span className="eyebrow eyebrow--coral">PLAN · DRAFT</span>
            <h1 className="h-display" style={{ fontSize: 28 }}>{PLAN.name}.</h1>
            <span className="dek" style={{ marginLeft: 6 }}>— {PLAN.weeks}-week half marathon block —</span>
          </div>
          <div style={{ display: "flex", gap: 10 }}>
            <button className="btn btn--ghost">Save draft</button>
            <button className="btn btn--primary">Publish ↗</button>
          </div>
        </div>

        {/* Sticky options strip */}
        <div style={{
          display: "grid",
          gridTemplateColumns: "auto auto 1fr auto",
          gap: 28,
          alignItems: "center",
          padding: "16px 0",
          borderBottom: "1px solid var(--rule)",
        }}>
          {/* Plan type — segmented */}
          <div style={{ display: "flex", gap: 0, border: "1px solid var(--rule)", borderRadius: 8, overflow: "hidden" }}>
            <button className="pill" style={{ border: 0, borderRadius: 0, padding: "8px 14px" }}>Fixed</button>
            <button className="pill is-active-adaptive" style={{ border: 0, borderRadius: 0, padding: "8px 14px" }}>Adaptive</button>
          </div>
          {/* Target distance */}
          <div style={{ display: "flex", gap: 6 }}>
            {["Marathon", "Half", "10K", "5K", "Custom"].map((d, i) => (
              <button key={d} className={"pill" + (i === 1 ? " is-active" : "")}>{d}</button>
            ))}
          </div>
          {/* Pace ref */}
          <div style={{ display: "flex", alignItems: "center", gap: 16, padding: "8px 14px", background: "var(--card)", borderRadius: 8, border: "1px solid var(--rule)" }}>
            <div style={{ display: "flex", flexDirection: "column", gap: 1 }}>
              <span className="eyebrow" style={{ fontSize: 9 }}>PACE REF</span>
              <span className="dek" style={{ fontSize: 10, color: "var(--coral)" }}>{PLAN.paceRef.source}</span>
            </div>
            {PLAN.paceRef.paces.map(p => (
              <div key={p.z} style={{ display: "flex", alignItems: "baseline", gap: 4 }}>
                <span className="mono" style={{ fontSize: 9, color: "var(--ink-2)", letterSpacing: "0.10em", textTransform: "uppercase" }}>{p.z}</span>
                <span className="mono" style={{ fontSize: 13, fontWeight: 600, color: "var(--ink)" }}>{p.v}</span>
              </div>
            ))}
            <button className="btn btn--link" style={{ fontSize: 11, marginLeft: 4 }}>edit</button>
          </div>
          {/* Weeks input */}
          <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <span className="mono" style={{ fontSize: 22, fontWeight: 600, color: "var(--ink)", border: "1px solid var(--rule)", padding: "4px 14px", borderRadius: 8 }}>{PLAN.weeks}</span>
            <span className="mono" style={{ fontSize: 10, color: "var(--ink-2)", letterSpacing: "0.10em", textTransform: "uppercase" }}>weeks</span>
          </div>
        </div>

        {/* Week navigator — horizontal mileage bars for each week */}
        <div style={{ display: "flex", gap: 14, padding: "20px 0 16px 0", borderBottom: "1px solid var(--rule)" }}>
          {[
            { w: 1, miles: 24.5, range: "50–70", active: true },
            { w: 2, miles: 0,    range: "—",    active: false },
          ].map(wk => (
            <div key={wk.w} style={{
              flex: 1,
              display: "flex",
              flexDirection: "column",
              gap: 6,
              padding: 12,
              borderRadius: 8,
              background: wk.active ? "var(--card)" : "transparent",
              border: "1px solid " + (wk.active ? "var(--coral)" : "var(--rule)"),
              cursor: "pointer",
            }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
                <span style={{ fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 18, color: wk.active ? "var(--coral)" : "var(--ink-3)" }}>Week {wk.w}</span>
                <span className="mono" style={{ fontSize: 11, fontWeight: 600, color: wk.active ? "var(--ink)" : "var(--ink-3)" }}>{wk.miles > 0 ? `${wk.miles} mi` : "—"}</span>
              </div>
              <div style={{ display: "flex", height: 5, background: "var(--paper-deep)", borderRadius: 999, overflow: "hidden" }}>
                <div style={{ background: wk.active ? "var(--coral)" : "var(--ink-3)", width: wk.miles > 0 ? (wk.miles / 70 * 100) + "%" : 0 }}></div>
              </div>
              <span className="mono" style={{ fontSize: 9, letterSpacing: "0.10em", color: "var(--ink-3)", textTransform: "uppercase" }}>RANGE {wk.range} MPW</span>
            </div>
          ))}
        </div>

        {/* Week 1 header */}
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-end", padding: "24px 0 14px 0" }}>
          <div>
            <span className="eyebrow eyebrow--coral">WEEK 01 · BUILD</span>
            <h2 className="h-display" style={{ fontSize: 22, marginTop: 4 }}>Quality on Tue, long on Sat.</h2>
          </div>
          <div style={{ display: "flex", gap: 24, alignItems: "baseline" }}>
            <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end", gap: 2 }}>
              <span className="eyebrow" style={{ fontSize: 9 }}>RANGE</span>
              <span className="mono" style={{ fontSize: 14, fontWeight: 600 }}>{PLAN.week.rangeMin}–{PLAN.week.rangeMax} <span style={{ fontSize: 10, color: "var(--ink-2)" }}>mpw</span></span>
            </div>
            <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end", gap: 2 }}>
              <span className="eyebrow" style={{ fontSize: 9 }}>QUALITY</span>
              <span className="mono" style={{ fontSize: 14, fontWeight: 600, color: "var(--mood-energized)" }}>{PLAN.week.quality} <span style={{ fontSize: 10, color: "var(--ink-2)" }}>mi</span></span>
            </div>
          </div>
        </div>

        {/* Bar chart row */}
        <div style={{ display: "grid", gridTemplateColumns: "repeat(7, 1fr)", gap: 8, alignItems: "flex-end", padding: "8px 0 0 0", height: 140 }}>
          {PLAN.week.days.map(d => {
            const isAuto = d.type === "auto";
            const miles = d.miles || (isAuto ? 4 : 0); // auto = est easy 4mi for chart shape
            const height = (miles / maxMiles) * 100;
            const isQuality = !isAuto;
            return (
              <div key={d.name} style={{ display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "flex-end", height: "100%", gap: 4, position: "relative" }}>
                <span className="mono" style={{ fontSize: 10, fontWeight: 600, color: isQuality ? "var(--ink)" : "var(--ink-3)" }}>
                  {d.miles ? d.miles : (isAuto ? "~" : "—")}
                </span>
                <div style={{
                  width: "70%",
                  height: height + "%",
                  background: isQuality ? "var(--coral)" : "var(--ink-3)",
                  opacity: isAuto ? 0.35 : 1,
                  borderRadius: "3px 3px 0 0",
                  minHeight: 4,
                }}></div>
              </div>
            );
          })}
        </div>

        {/* Day labels */}
        <div style={{ display: "grid", gridTemplateColumns: "repeat(7, 1fr)", gap: 8, padding: "8px 0", borderBottom: "1px solid var(--rule)" }}>
          {PLAN.week.days.map(d => (
            <span key={d.name} className="eyebrow" style={{ textAlign: "center", fontSize: 10 }}>{d.name.toUpperCase()}</span>
          ))}
        </div>

        {/* Editable rows — under the chart */}
        <div style={{ display: "grid", gridTemplateColumns: "repeat(7, 1fr)", gap: 8, padding: "16px 0 0 0" }}>
          {PLAN.week.days.map(d => {
            const isAuto = d.type === "auto";
            return (
              <div key={d.name} style={{
                padding: 12,
                background: isAuto ? "transparent" : "var(--card)",
                border: "1px solid " + (isAuto ? "var(--rule)" : "transparent"),
                borderRadius: 6,
                minHeight: 80,
                display: "flex",
                flexDirection: "column",
                gap: 6,
                cursor: "pointer",
              }}>
                {isAuto ? (
                  <>
                    <span className="dek" style={{ fontSize: 11, color: "var(--ink-3)" }}>Auto · easy run</span>
                    <span className="mono" style={{ fontSize: 9, color: "var(--ink-3)", letterSpacing: "0.10em", textTransform: "uppercase" }}>per athlete</span>
                  </>
                ) : (
                  <>
                    <span className="eyebrow" style={{ fontSize: 9, color: "var(--coral)" }}>{d.type.replace("_", " ").toUpperCase()}</span>
                    <span style={{ fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 14, color: "var(--ink)", lineHeight: 1.2 }}>{d.title}</span>
                    <span className="mono" style={{ fontSize: 11, fontWeight: 600, color: "var(--ink)" }}>{d.miles} mi</span>
                  </>
                )}
              </div>
            );
          })}
        </div>

      </main>
    </div>
  );
};

window.PlanBuilderB = PlanBuilderB;

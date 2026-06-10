// Direction A — Editorial / The Plate
// The plan builder reads like a magazine spread. Plate strip,
// big display headline, italic dek, vertical day-by-day diary.

const PlanBuilderA = () => (
  <div className="app-shell">
    <Sidebar />
    <main style={{ padding: "32px 48px 56px 48px", overflow: "auto" }}>

      {/* Plate strip */}
      <div className="plate-strip">
        <div className="stack">
          <span>COACH PORTAL</span>
          <span>— PLAN BUILDER · v1</span>
        </div>
        <div className="stack" style={{ textAlign: "right" }}>
          <span>FIG. 04</span>
          <span>DRAFT · 13.05.2026</span>
        </div>
      </div>

      {/* Title row */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-end", padding: "32px 0 18px 0" }}>
        <div>
          <span className="eyebrow eyebrow--coral">DRAFT · {PLAN.weeks} WEEKS</span>
          <h1 className="h-display" style={{ fontSize: 56, marginTop: 8 }}>{PLAN.name}.</h1>
          <div className="dek" style={{ marginTop: 8 }}>
            — half marathon block · adaptive · {PLAN.weeks} weeks out —
          </div>
        </div>
        <div style={{ display: "flex", gap: 12, alignItems: "center" }}>
          <button className="btn btn--ghost">Save draft</button>
          <button className="btn btn--primary">Publish ↗</button>
        </div>
      </div>

      {/* Plan options as inline editorial captions */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 32, padding: "16px 0 8px 0", borderTop: "1px solid var(--rule)", borderBottom: "1px solid var(--rule)" }}>
        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
          <span className="eyebrow">Plan type</span>
          <div style={{ display: "flex", gap: 14, alignItems: "baseline" }}>
            <span style={{ fontFamily: "var(--font-display)", fontSize: 24, color: "var(--ink-3)", fontWeight: 700 }}>Fixed</span>
            <span className="mono" style={{ fontSize: 12, color: "var(--ink-3)" }}>·</span>
            <span style={{ fontFamily: "var(--font-display)", fontSize: 24, color: "var(--coral)", fontWeight: 700, borderBottom: "2px solid var(--coral)" }}>Adaptive</span>
            <span className="dek" style={{ fontSize: 11, marginLeft: 12 }}>— per-athlete easy days, fixed quality.</span>
          </div>
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
          <span className="eyebrow">Target</span>
          <div style={{ display: "flex", gap: 14, alignItems: "baseline" }}>
            {["Marathon", "Half marathon", "10K", "5K", "Custom"].map((d, i) => (
              <span key={d}
                style={{
                  fontFamily: "var(--font-display)",
                  fontSize: 18,
                  fontWeight: 700,
                  color: i === 1 ? "var(--coral)" : "var(--ink-3)",
                  borderBottom: i === 1 ? "2px solid var(--coral)" : "none",
                }}>
                {d}
              </span>
            ))}
            <span className="dek" style={{ fontSize: 11, marginLeft: 8 }}>· <span className="mono" style={{ color: "var(--ink)", fontWeight: 600 }}>{PLAN.weeks}</span> weeks</span>
          </div>
        </div>
      </div>

      {/* Pace reference */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", padding: "20px 0", borderBottom: "1px solid var(--rule)" }}>
        <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
          <span className="eyebrow">Pace reference</span>
          <span className="dek" style={{ color: "var(--coral)", fontSize: 12 }}>{PLAN.paceRef.source}</span>
        </div>
        <div style={{ display: "flex", gap: 32, alignItems: "baseline" }}>
          {PLAN.paceRef.paces.map(p => (
            <div key={p.z} style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 2 }}>
              <span className="eyebrow" style={{ fontSize: 9 }}>{p.z}</span>
              <span className="mono" style={{ fontSize: 18, fontWeight: 600, color: "var(--ink)" }}>{p.v}</span>
            </div>
          ))}
        </div>
        <button className="btn btn--link">Edit paces</button>
      </div>

      {/* Week tabs */}
      <div style={{ display: "flex", alignItems: "center", gap: 24, padding: "26px 0 18px 0" }}>
        <span className="eyebrow">Weeks</span>
        {[1, 2].map(n => (
          <div key={n} style={{
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 4,
            cursor: "pointer",
            opacity: n === 1 ? 1 : 0.5,
          }}>
            <span style={{
              fontFamily: "var(--font-display)",
              fontSize: 28,
              fontWeight: 700,
              color: n === 1 ? "var(--coral)" : "var(--ink-3)",
              lineHeight: 1,
            }}>W{n}</span>
            <span className="mono" style={{ fontSize: 9, color: "var(--ink-3)" }}>
              {n === 1 ? "● 7 WORKOUTS" : "○ DRAFT"}
            </span>
          </div>
        ))}
        <div style={{ flex: 1 }}></div>
        <div style={{ display: "flex", gap: 24, alignItems: "baseline" }}>
          <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end" }}>
            <span className="eyebrow" style={{ fontSize: 9 }}>RANGE</span>
            <span className="mono" style={{ fontSize: 14, fontWeight: 600, color: "var(--ink)" }}>{PLAN.week.rangeMin}–{PLAN.week.rangeMax} <span style={{ fontSize: 10, color: "var(--ink-2)" }}>mpw</span></span>
          </div>
          <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end" }}>
            <span className="eyebrow" style={{ fontSize: 9 }}>QUALITY</span>
            <span className="mono" style={{ fontSize: 14, fontWeight: 600, color: "var(--mood-energized)" }}>{PLAN.week.quality} <span style={{ fontSize: 10, color: "var(--ink-2)" }}>mi</span></span>
          </div>
        </div>
      </div>

      {/* Section heading */}
      <div style={{ marginTop: 12 }}>
        <div className="rule"><span className="d"></span></div>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-end", marginTop: 18, marginBottom: 8 }}>
          <div>
            <span className="eyebrow eyebrow--coral">WEEK 01 OF 02</span>
            <h2 className="h-display" style={{ fontSize: 28, marginTop: 4 }}>Build, with one quality block.</h2>
          </div>
          <span className="dek">— quality only · easy days fill per athlete —</span>
        </div>
      </div>

      {/* Day-by-day list */}
      <div style={{ marginTop: 12 }}>
        {PLAN.week.days.map((d, i) => {
          const isAuto = d.type === "auto";
          const isQuality = !isAuto;
          return (
            <div key={d.name} style={{
              display: "grid",
              gridTemplateColumns: "80px 1fr auto 40px",
              gap: 24,
              alignItems: "baseline",
              padding: isQuality ? "20px 0" : "14px 0",
              borderTop: "1px solid var(--rule)",
              opacity: isAuto ? 0.7 : 1,
            }}>
              <span className="eyebrow" style={{ fontSize: 11, color: isQuality ? "var(--coral)" : "var(--ink-3)", fontWeight: isQuality ? 600 : 500 }}>{d.name.toUpperCase()}</span>
              <div>
                {isQuality ? (
                  <>
                    <div style={{ fontFamily: "var(--font-display)", fontSize: 22, fontWeight: 700, color: "var(--ink)", letterSpacing: "-0.01em" }}>
                      {d.title}
                    </div>
                    <div className="mono" style={{ fontSize: 11, color: "var(--ink-2)", letterSpacing: "0.10em", textTransform: "uppercase", marginTop: 4 }}>
                      {d.type.toUpperCase().replace("_", " ")} &nbsp;·&nbsp; {d.miles} MI
                    </div>
                  </>
                ) : (
                  <span className="dek">{d.title}</span>
                )}
              </div>
              <span className="mono" style={{ fontSize: 14, fontWeight: 600, color: isQuality ? "var(--ink)" : "var(--ink-3)" }}>
                {d.miles ? `${d.miles} mi` : "—"}
              </span>
              <span style={{ fontFamily: "var(--font-mono)", color: "var(--ink-3)", fontSize: 20, cursor: "pointer" }}>+</span>
            </div>
          );
        })}
        <div style={{ borderTop: "1px solid var(--rule)", height: 1 }}></div>
      </div>

    </main>
  </div>
);

window.PlanBuilderA = PlanBuilderA;

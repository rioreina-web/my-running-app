// Direction C — Newspaper / Two-column
// Like a newspaper sports page. Left rail: plan meta + paces + week
// nav. Right column (wider): the 7 days as full editorial entries.

const PlanBuilderC = () => (
  <div className="app-shell">
    <Sidebar />
    <main style={{ padding: "28px 36px 36px 36px", overflow: "auto" }}>

      {/* Plate strip */}
      <div className="plate-strip">
        <div className="stack">
          <span>POST RUN DRIP</span>
          <span>— THE COACH'S DESK · MAY 13, 2026</span>
        </div>
        <div className="stack" style={{ textAlign: "right" }}>
          <span>PLAN BUILDER</span>
          <span>VOL. 04 · NO. 02 · DRAFT</span>
        </div>
      </div>

      {/* Masthead title row */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-end", padding: "28px 0 18px 0", borderBottom: "2px solid var(--ink)" }}>
        <div>
          <span className="eyebrow eyebrow--coral">A {PLAN.weeks}-WEEK HALF MARATHON PLAN, ADAPTIVE</span>
          <h1 className="h-display" style={{ fontSize: 48, marginTop: 6 }}>{PLAN.name}.</h1>
          <div className="dek" style={{ marginTop: 6 }}>— quality fixed, easy days fill per athlete —</div>
        </div>
        <div style={{ display: "flex", gap: 10 }}>
          <button className="btn btn--ghost">Save draft</button>
          <button className="btn btn--primary">Publish ↗</button>
        </div>
      </div>

      {/* Two-column body */}
      <div style={{ display: "grid", gridTemplateColumns: "260px 1fr", gap: 36, paddingTop: 28 }}>

        {/* LEFT RAIL */}
        <aside style={{ display: "flex", flexDirection: "column", gap: 22 }}>

          {/* Plan type */}
          <section>
            <span className="eyebrow">Plan type</span>
            <div style={{ display: "flex", gap: 0, marginTop: 8, border: "1px solid var(--rule)", borderRadius: 8, overflow: "hidden" }}>
              <button className="pill" style={{ flex: 1, border: 0, borderRadius: 0 }}>Fixed</button>
              <button className="pill is-active-adaptive" style={{ flex: 1, border: 0, borderRadius: 0 }}>Adaptive</button>
            </div>
          </section>

          {/* Target distance */}
          <section>
            <span className="eyebrow">Target distance</span>
            <div style={{ display: "flex", flexDirection: "column", gap: 4, marginTop: 8 }}>
              {[
                { d: "Marathon", n: 26.2 },
                { d: "Half marathon", n: 13.1, active: true },
                { d: "10K", n: 6.2 },
                { d: "5K", n: 3.1 },
                { d: "Custom", n: null },
              ].map(item => (
                <div key={item.d} style={{
                  display: "flex",
                  justifyContent: "space-between",
                  alignItems: "baseline",
                  padding: "6px 10px",
                  borderRadius: 4,
                  background: item.active ? "rgba(212, 89, 42, 0.06)" : "transparent",
                  cursor: "pointer",
                }}>
                  <span style={{ fontFamily: "var(--font-display)", fontSize: 14, fontWeight: 600, color: item.active ? "var(--coral)" : "var(--ink)" }}>{item.d}</span>
                  {item.n && <span className="mono" style={{ fontSize: 10, color: "var(--ink-3)" }}>{item.n} mi</span>}
                </div>
              ))}
            </div>
          </section>

          {/* Duration */}
          <section>
            <span className="eyebrow">Duration</span>
            <div style={{ display: "flex", alignItems: "baseline", gap: 8, marginTop: 8 }}>
              <span style={{ fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 36, color: "var(--ink)" }}>{PLAN.weeks}</span>
              <span className="dek" style={{ fontSize: 11 }}>weeks · ends 27 May</span>
            </div>
          </section>

          <div className="hairline"></div>

          {/* Pace reference */}
          <section>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginBottom: 8 }}>
              <span className="eyebrow">Pace reference</span>
              <button className="btn btn--link" style={{ fontSize: 11 }}>edit</button>
            </div>
            <p className="dek" style={{ fontSize: 11, color: "var(--coral)", margin: "0 0 10px 0" }}>{PLAN.paceRef.source}</p>
            <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
              {PLAN.paceRef.paces.map(p => (
                <div key={p.z} style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", padding: "4px 0", borderBottom: "1px solid var(--rule)" }}>
                  <span className="mono" style={{ fontSize: 10, color: "var(--ink-2)", letterSpacing: "0.10em", textTransform: "uppercase", fontWeight: 600 }}>{p.z}</span>
                  <span className="mono" style={{ fontSize: 14, fontWeight: 600, color: "var(--ink)" }}>{p.v}</span>
                </div>
              ))}
            </div>
          </section>

          <div className="hairline"></div>

          {/* Week navigator */}
          <section>
            <span className="eyebrow">Weeks</span>
            <div style={{ display: "flex", flexDirection: "column", gap: 6, marginTop: 8 }}>
              {[1, 2].map(n => (
                <div key={n} style={{
                  display: "flex", justifyContent: "space-between", alignItems: "baseline",
                  padding: "10px 12px",
                  borderRadius: 6,
                  background: n === 1 ? "var(--card)" : "transparent",
                  border: "1px solid " + (n === 1 ? "var(--coral)" : "var(--rule)"),
                  cursor: "pointer",
                }}>
                  <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
                    <span style={{ fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 14, color: n === 1 ? "var(--coral)" : "var(--ink)" }}>Week {n}</span>
                    <span className="mono" style={{ fontSize: 9, color: "var(--ink-3)", letterSpacing: "0.10em", textTransform: "uppercase" }}>{n === 1 ? "7 WORKOUTS" : "DRAFT"}</span>
                  </div>
                  <span className="mono" style={{ fontSize: 12, fontWeight: 600, color: n === 1 ? "var(--ink)" : "var(--ink-3)" }}>
                    {n === 1 ? `${PLAN.week.quality} mi` : "—"}
                  </span>
                </div>
              ))}
            </div>
          </section>

        </aside>

        {/* RIGHT COLUMN */}
        <section>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-end", marginBottom: 18 }}>
            <div>
              <span className="eyebrow eyebrow--coral">WEEK 01 · BUILD</span>
              <h2 className="h-display" style={{ fontSize: 28, marginTop: 4 }}>Quality on Tue. Long on Sat.</h2>
              <div className="dek" style={{ marginTop: 4 }}>— easy days fill per athlete when they subscribe —</div>
            </div>
            <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end", gap: 4 }}>
              <span className="eyebrow" style={{ fontSize: 9 }}>RANGE</span>
              <span className="mono" style={{ fontSize: 18, fontWeight: 600 }}>{PLAN.week.rangeMin}–{PLAN.week.rangeMax} <span style={{ fontSize: 10, color: "var(--ink-2)" }}>mpw</span></span>
              <span className="mono" style={{ fontSize: 10, color: "var(--mood-energized)", letterSpacing: "0.10em", textTransform: "uppercase", fontWeight: 600, marginTop: 2 }}>{PLAN.week.quality} MI QUALITY</span>
            </div>
          </div>

          <div className="hairline" style={{ marginBottom: 0 }}></div>

          {/* Day entries — magazine "stories" */}
          {PLAN.week.days.map((d, i) => {
            const isAuto = d.type === "auto";
            return (
              <div key={d.name} style={{
                display: "grid",
                gridTemplateColumns: "76px 1fr auto",
                gap: 20,
                alignItems: "baseline",
                padding: isAuto ? "14px 0" : "22px 0",
                borderBottom: "1px solid var(--rule)",
              }}>
                <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
                  <span className="eyebrow" style={{ fontSize: 11, color: !isAuto ? "var(--coral)" : "var(--ink-2)", fontWeight: !isAuto ? 600 : 500 }}>{d.name.toUpperCase()}</span>
                  {!isAuto && <span className="mono" style={{ fontSize: 9, color: "var(--ink-3)", letterSpacing: "0.10em", textTransform: "uppercase" }}>{d.type.replace("_", " ")}</span>}
                </div>
                <div>
                  {isAuto ? (
                    <span className="dek" style={{ fontSize: 13 }}>Auto · easy run · per athlete</span>
                  ) : (
                    <>
                      <div style={{ fontFamily: "var(--font-display)", fontSize: 24, fontWeight: 700, color: "var(--ink)", letterSpacing: "-0.01em" }}>
                        {d.title}
                      </div>
                      <div className="dek" style={{ marginTop: 6, fontStyle: "italic" }}>
                        {d.type === "tempo"
                          ? "— 3 mi @ LT, then 2 mi at LT-2%. Steady, controlled, no surges. —"
                          : d.type === "long_run"
                          ? "— 15 miles steady. Last 3 miles at MP if the legs allow. —"
                          : ""}
                      </div>
                    </>
                  )}
                </div>
                <div style={{ display: "flex", alignItems: "baseline", gap: 12 }}>
                  <span className="mono" style={{ fontSize: 18, fontWeight: 600, color: !isAuto ? "var(--ink)" : "var(--ink-3)" }}>
                    {d.miles ? `${d.miles}` : "—"}
                  </span>
                  {d.miles && <span className="mono" style={{ fontSize: 10, color: "var(--ink-2)", letterSpacing: "0.10em", textTransform: "uppercase" }}>mi</span>}
                  <span style={{ fontFamily: "var(--font-mono)", color: "var(--ink-3)", fontSize: 18, marginLeft: 6, cursor: "pointer" }}>+</span>
                </div>
              </div>
            );
          })}

          <div style={{ paddingTop: 16, display: "flex", justifyContent: "center" }}>
            <button className="btn btn--link">+ Add a quality day</button>
          </div>
        </section>

      </div>

    </main>
  </div>
);

window.PlanBuilderC = PlanBuilderC;

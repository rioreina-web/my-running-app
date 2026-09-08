/* global React, window */
/* ============================================================
   Shared shell + small UI atoms for the Pace × Volume studies.
   PhoneScreen frame, section header, ALL/WORKOUTS toggle,
   pointer-x hook, tiny sparkline. Attached to window.
   ============================================================ */
(function () {
  "use strict";
  const { useState, useRef, useCallback } = React;
  const PV = window.PV;

  /* --- a clean iPhone-ish screen card (no heavy bezel) ------- */
  function PhoneScreen({ children }) {
    return (
      <div style={{
        width: "100%", minHeight: "100%", background: "var(--paper)",
        fontFamily: "var(--font-body)", color: "var(--ink)",
        display: "flex", flexDirection: "column",
      }}>
        {/* status bar */}
        <div style={{
          display: "flex", justifyContent: "space-between", alignItems: "center",
          padding: "14px 26px 4px", fontFamily: "var(--font-mono)",
          fontSize: 13, fontWeight: 600, color: "var(--ink)",
        }}>
          <span>8:03</span>
          <span style={{ display: "flex", gap: 5, alignItems: "center", opacity: .85 }}>
            <span style={{ fontSize: 11, letterSpacing: 1 }}>•••</span>
            <span style={{ fontSize: 12 }}>􀙇</span>
            <span style={{
              width: 22, height: 11, border: "1.5px solid var(--ink)", borderRadius: 3,
              display: "inline-block", position: "relative",
            }}>
              <span style={{ position: "absolute", inset: 1.5, background: "var(--ink)", borderRadius: 1 }} />
            </span>
          </span>
        </div>
        {children}
        <div style={{ flexGrow: 1 }} />
        {/* home indicator */}
        <div style={{ display: "flex", justifyContent: "center", padding: "10px 0 12px" }}>
          <span style={{ width: 134, height: 5, borderRadius: 3, background: "var(--ink)", opacity: .35 }} />
        </div>
      </div>
    );
  }

  /* --- section header w/ eyebrow + ALL/WORKOUTS toggle ------- */
  function SectionHead({ mode, setMode }) {
    return (
      <div style={{ padding: "0 22px" }}>
        <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between" }}>
          <span style={{
            fontFamily: "var(--font-mono)", fontSize: 11, fontWeight: 500,
            letterSpacing: "1.3px", color: "var(--ink-2)",
          }}>PACE&nbsp;&nbsp;&amp;&nbsp;&nbsp;VOLUME&nbsp;&nbsp;·&nbsp;&nbsp;9&nbsp;WEEKS</span>
          <div style={{ display: "flex", gap: 14 }}>
            {[["all", "ALL"], ["workouts", "WORKOUTS"]].map(([id, lbl]) => (
              <button key={id} onClick={() => setMode(id)} style={{
                all: "unset", cursor: "pointer", fontFamily: "var(--font-mono)",
                fontSize: 10, fontWeight: 500, letterSpacing: "1.1px",
                color: mode === id ? "var(--ink)" : "var(--ink-3)",
                paddingBottom: 3, borderBottom: "1.5px solid " + (mode === id ? "var(--coral)" : "transparent"),
              }}>{lbl}</button>
            ))}
          </div>
        </div>
        <div style={{ height: 1, background: "var(--rule)", margin: "12px 0 4px" }} />
      </div>
    );
  }

  /* --- pointer x position (0..1) over an element ------------- */
  function usePointerX() {
    const [t, setT] = useState(null);     // null = not scrubbing
    const ref = useRef(null);
    const move = useCallback((e) => {
      const el = ref.current; if (!el) return;
      const rect = el.getBoundingClientRect();
      const cx = (e.touches ? e.touches[0].clientX : e.clientX) - rect.left;
      setT(Math.min(Math.max(cx / rect.width, 0), 1));
    }, []);
    const leave = useCallback(() => setT(null), []);
    return { t, setT, ref, bind: {
      onMouseMove: move, onMouseLeave: leave,
      onTouchStart: move, onTouchMove: (e) => { e.preventDefault(); move(e); }, onTouchEnd: leave,
    } };
  }

  /* --- tiny sparkline (faster-is-down line) ------------------ */
  function Sparkline({ values, w = 52, h = 16, color = "var(--coral)" }) {
    const vals = values.filter((v) => v != null);
    if (vals.length < 2) return <svg width={w} height={h} />;
    const min = Math.min(...vals), max = Math.max(...vals);
    const span = max - min || 1;
    const pts = values.map((v, i) => {
      const x = (i / (values.length - 1)) * w;
      const y = v == null ? null : h - 2 - ((max - v) / span) * (h - 4); // faster(lower sec)=down? invert: lower sec=better=up
      return v == null ? null : [x, h - 2 - ((v - min) / span) * (h - 4)];
    }).filter(Boolean);
    const d = pts.map((p, i) => (i ? "L" : "M") + p[0].toFixed(1) + " " + p[1].toFixed(1)).join(" ");
    return (
      <svg width={w} height={h} style={{ display: "block" }}>
        <path d={d} fill="none" stroke={color} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
        <circle cx={pts[pts.length - 1][0]} cy={pts[pts.length - 1][1]} r="1.8" fill={color} />
      </svg>
    );
  }

  /* --- shared screen chrome: title + block totals ----------- */
  function Chrome({ caption }) {
    const s = window.PV.SUMMARY;
    const totals = [
      { lbl: "BLOCK TOTAL", val: String(s.blockTotal), unit: "MI" },
      { lbl: "AVG WEEK", val: String(s.avgWeek), unit: "MI" },
      { lbl: "LONG RUN", val: String(s.longRun), unit: "MI" },
    ];
    return (
      <div style={{ padding: "10px 22px 0" }}>
        <div style={{
          fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 500,
          letterSpacing: "1.3px", color: "var(--coral)",
        }}>THE BLOCK&nbsp;&nbsp;·&nbsp;&nbsp;WEEK&nbsp;04&nbsp;OF&nbsp;20</div>
        <div style={{
          fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 30,
          letterSpacing: "-0.015em", lineHeight: 1.04, marginTop: 4,
        }}>Half marathon block.</div>
        {caption && (
          <div style={{
            fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13.5,
            color: "var(--ink-2)", marginTop: 6, lineHeight: 1.4,
          }}>{caption}</div>
        )}
        <div style={{ display: "grid", gridTemplateColumns: "repeat(3,1fr)", marginTop: 16, marginBottom: 6 }}>
          {totals.map((s, i) => (
            <div key={s.lbl} style={{
              borderRight: i < 2 ? "1px solid var(--rule)" : "0", paddingRight: 12,
              paddingLeft: i ? 16 : 0,
            }}>
              <div style={{
                fontFamily: "var(--font-mono)", fontSize: 9.5, fontWeight: 500,
                letterSpacing: "0.9px", color: "var(--ink-2)",
              }}>{s.lbl}</div>
              <div style={{ display: "flex", alignItems: "baseline", gap: 4, marginTop: 5 }}>
                <span style={{
                  fontFamily: "var(--font-mono)", fontWeight: 600, fontSize: 30,
                  letterSpacing: "-0.5px", color: "var(--ink)", fontVariantNumeric: "tabular-nums",
                }}>{s.val}</span>
                <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--ink-2)" }}>{s.unit}</span>
              </div>
            </div>
          ))}
        </div>
      </div>
    );
  }

  window.PVUI = { PhoneScreen, SectionHead, usePointerX, Sparkline, Chrome };
})();

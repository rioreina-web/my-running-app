/* global React, window */
/* ============================================================
   PACE × VOLUME — STUDIO SWITCHER
   One phone, five graph styles. A segmented control swaps the
   chart body; the ALL/WORKOUTS toggle and block chrome stay
   put. Pass `lock="<id>"` to pin one style and hide the tabs
   (used for the side-by-side comparison row).
   ============================================================ */
(function () {
  "use strict";
  const { useState } = React;
  const { PhoneScreen, SectionHead, Chrome } = window.PVUI;

  const STYLES = [
    { id: "spectrum", label: "Curve",  caption: "Where every mile of the block actually landed.", get: () => window.SpectrumBody },
    { id: "ledger",   label: "Ledger", caption: "A ledger of the block — miles by training zone.", get: () => window.LedgerBody },
    { id: "strip",    label: "Dots",   caption: "One dot per run. Bigger dot, more miles.",         get: () => window.StripBody },
    { id: "weekly",   label: "Build",  caption: "How the block built — week by week, zone by zone.", get: () => window.WeeklyBody },
    { id: "ring",     label: "Ring",   caption: "The whole block as one wheel of zones.",            get: () => window.RingBody },
  ];

  function StyleTabs({ active, onPick }) {
    return (
      <div style={{ padding: "12px 22px 0" }}>
        <div style={{ display: "flex", gap: 3, padding: 4, background: "var(--paper-deep)", borderRadius: 11 }}>
          {STYLES.map((s) => {
            const on = active === s.id;
            return (
              <button key={s.id} onClick={() => onPick(s.id)} style={{
                all: "unset", flex: 1, textAlign: "center", cursor: "pointer", boxSizing: "border-box",
                fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 600, letterSpacing: ".5px",
                padding: "7px 0", borderRadius: 8,
                color: on ? "var(--paper)" : "var(--ink-2)",
                background: on ? "var(--ink)" : "transparent",
                transition: "background .15s, color .15s",
              }}>{s.label.toUpperCase()}</button>
            );
          })}
        </div>
      </div>
    );
  }

  function PVStudio({ initial = "spectrum", lock = null }) {
    const [styleId, setStyleId] = useState(initial);
    const [mode, setMode] = useState("all");
    const activeId = lock || styleId;
    const active = STYLES.find((s) => s.id === activeId) || STYLES[0];
    const Body = active.get();

    return (
      <PhoneScreen>
        <Chrome caption={active.caption} />
        {!lock && <StyleTabs active={active.id} onPick={setStyleId} />}
        <SectionHead mode={mode} setMode={setMode} />
        {Body ? <Body mode={mode} /> : null}
      </PhoneScreen>
    );
  }

  window.PVStudio = PVStudio;
  window.PV_STYLES = STYLES;
})();

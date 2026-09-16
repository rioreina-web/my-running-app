/* global React */
/* ════════════════════════════════════════════════════════════════════
   APP MENU · BRAND REBRAND
   The slide-over navigation, redrawn in the editorial voice.
   Kills: pastel coral circle-icons, white card-in-card rows.
   Adds:  a typographic index (numbered table-of-contents), an athlete
          masthead for context, hairline dividers, coral held to a single
          hit per cluster (the PRO tag; the live hover state).
   ════════════════════════════════════════════════════════════════════ */

const MENU_CSS = `
/* ---- Backdrop (the dimmed app behind) -------------------------------- */
.mnu-stage { position: relative; height: 100%; overflow: hidden; background: var(--paper); }
.mnu-scrim {
  position: absolute; inset: 0; z-index: 2;
  background: rgba(26, 24, 21, 0.46);
  opacity: 0; pointer-events: none;
  transition: opacity .28s ease-out;
}
.mnu-stage.is-open .mnu-scrim { opacity: 1; pointer-events: auto; }

/* ---- Panel ----------------------------------------------------------- */
.mnu-panel {
  position: absolute; top: 0; bottom: 0; left: 0; z-index: 3;
  width: 85%;
  background: var(--paper);
  box-shadow: 2px 0 28px rgba(0,0,0,0.22);
  display: flex; flex-direction: column;
  transform: translateX(-101%);
  transition: transform .34s cubic-bezier(0.22, 1, 0.36, 1);
}
.mnu-stage.is-open .mnu-panel { transform: translateX(0); }

/* ---- Masthead -------------------------------------------------------- */
.mnu-head { padding: 16px 22px 14px 24px; }
.mnu-toprow {
  display: flex; align-items: flex-start; justify-content: space-between;
}
.mnu-wordmark {
  font-family: var(--font-display);
  font-weight: 800; font-size: 15px; line-height: 0.92;
  letter-spacing: -0.01em; color: var(--ink);
  text-transform: lowercase;
}
.mnu-wordmark span:last-child { color: var(--coral); }
.mnu-close {
  width: 34px; height: 34px; flex: none;
  border: 1px solid var(--rule); border-radius: 999px;
  background: transparent; color: var(--ink-2);
  display: grid; place-items: center; cursor: pointer;
  font-family: var(--font-mono); font-size: 14px; line-height: 1;
  transition: all var(--dur-fast) var(--ease-out);
}
.mnu-close:hover { background: var(--ink); color: var(--paper); border-color: var(--ink); }

.mnu-platerow {
  display: flex; align-items: baseline; justify-content: space-between;
  margin-top: 18px;
}
.mnu-plate {
  font-family: var(--font-mono); font-size: 10px; font-weight: 500;
  letter-spacing: 0.14em; text-transform: uppercase; color: var(--ink-3);
  white-space: nowrap;
}

.mnu-identity {
  margin-top: 12px;
  display: flex; align-items: flex-end; justify-content: space-between; gap: 12px;
}
.mnu-idblock { min-width: 0; }
.mnu-name {
  font-family: var(--font-display); font-weight: 700;
  font-size: 28px; line-height: 1; letter-spacing: -0.015em; color: var(--ink);
  white-space: nowrap;
}
.mnu-email {
  font-family: var(--font-mono); font-size: 10px; letter-spacing: 0.06em;
  color: var(--ink-3); margin-top: 7px; white-space: nowrap;
}
.mnu-pro {
  flex: none; align-self: center;
  font-family: var(--font-mono); font-size: 9px; font-weight: 600;
  letter-spacing: 0.16em; color: var(--coral);
  background: var(--coral-wash); border-radius: 999px;
  padding: 5px 10px; text-transform: uppercase;
}

/* ---- Nav index ------------------------------------------------------- */
.mnu-nav { flex: 1; overflow-y: auto; padding: 4px 0 8px; }
.mnu-nav::-webkit-scrollbar { width: 0; }

.mnu-group { padding: 0 24px; }
.mnu-grouphead {
  display: flex; align-items: center; gap: 10px;
  padding: 16px 0 3px;
}
.mnu-grouphead .lbl {
  font-family: var(--font-mono); font-size: 10px; font-weight: 500;
  letter-spacing: 0.16em; text-transform: uppercase; color: var(--ink-2);
}
.mnu-grouphead .ln { flex: 1; height: 1px; background: var(--rule); }

.mnu-item {
  display: grid; grid-template-columns: 30px 1fr 16px;
  align-items: baseline; column-gap: 14px;
  padding: 13px 0 12px;
  border-bottom: 1px solid var(--rule);
  cursor: pointer;
  transition: padding-left var(--dur-fast) var(--ease-out);
}
.mnu-item:last-child { border-bottom: none; }
.mnu-num {
  font-family: var(--font-mono); font-size: 12px; font-weight: 500;
  letter-spacing: 0.04em; color: var(--ink-3);
  font-variant-numeric: tabular-nums;
  transition: color var(--dur-fast) var(--ease-out);
}
.mnu-label {
  font-family: var(--font-display); font-weight: 600; font-size: 19px;
  letter-spacing: -0.01em; color: var(--ink); line-height: 1.05;
}
.mnu-hint {
  font-family: var(--font-body); font-style: italic; font-size: 12.5px;
  color: var(--ink-3); margin-top: 3px; line-height: 1.4;
}
.mnu-arrow {
  font-family: var(--font-mono); font-size: 12px; color: var(--ink-3);
  align-self: center; text-align: right;
  transition: color var(--dur-fast) var(--ease-out), transform var(--dur-fast) var(--ease-out);
}
.mnu-item:hover { padding-left: 5px; }
.mnu-item:hover .mnu-num { color: var(--coral); }
.mnu-item:hover .mnu-arrow { color: var(--coral); transform: translate(2px, -2px); }

/* ---- Footer ---------------------------------------------------------- */
.mnu-foot {
  margin-top: auto;
  padding: 14px 24px 18px;
  border-top: 1px solid var(--rule);
  display: flex; align-items: baseline; justify-content: space-between; gap: 12px;
}
.mnu-signout {
  font-family: var(--font-display); font-weight: 600; font-size: 14px;
  color: var(--ink-2); cursor: pointer; white-space: nowrap; flex: none;
  border-bottom: 1px solid var(--rule); padding-bottom: 1px;
  transition: color var(--dur-fast) var(--ease-out), border-color var(--dur-fast) var(--ease-out);
}
.mnu-signout:hover { color: var(--coral); border-color: var(--coral); }
.mnu-build {
  font-family: var(--font-mono); font-size: 9px; letter-spacing: 0.1em;
  text-transform: uppercase; color: var(--ink-3); text-align: right; white-space: nowrap;
}

/* ---- Dimmed home fragments (peek behind panel) ----------------------- */
.mnu-bg { position: absolute; inset: 0; z-index: 1; padding: 22px; box-sizing: border-box;
  display: flex; flex-direction: column; }
.mnu-bg-top { display: flex; justify-content: flex-end; gap: 8px; }
.mnu-bg-gear, .mnu-bg-today {
  font-family: var(--font-mono); font-size: 11px; letter-spacing: 0.1em;
  color: var(--ink-2); border: 1px solid var(--rule); border-radius: 999px;
  padding: 7px 12px;
}
.mnu-bg-h { font-family: var(--font-display); font-weight: 700; font-size: 40px;
  line-height: 1; color: var(--ink); margin-top: 70px; letter-spacing: -0.02em; }
.mnu-bg-sub { font-family: var(--font-body); font-style: italic; font-size: 15px;
  color: var(--ink-2); margin-top: 12px; }
.mnu-bg-cta { font-family: var(--font-mono); font-size: 12px; letter-spacing: 0.12em;
  color: var(--ink); margin-top: 28px; text-transform: uppercase; }
`;

const MENU_GROUPS = [
  {
    head: "Targets",
    items: [
      { n: "01", id: "goals",     label: "Goals",            hint: "Race & training targets." },
      { n: "02", id: "pace",      label: "Pace Chart",       hint: "Your training paces, by zone." },
      { n: "03", id: "predictor", label: "Fitness Predictor", hint: "AI race-time predictions." },
    ],
  },
  {
    head: "Review",
    items: [
      { n: "04", id: "analysis",  label: "Training Analysis", hint: "Trends across your block." },
      { n: "05", id: "injuries",  label: "Injuries",          hint: "Track, analyze, recover." },
    ],
  },
  {
    head: "Library & Account",
    items: [
      { n: "06", id: "library",   label: "Content Library",   hint: "Films, drills & reading." },
      { n: "07", id: "settings",  label: "Settings",          hint: "Account, data & app preferences." },
    ],
  },
];

function MenuBackdrop() {
  return (
    <div className="mnu-bg" aria-hidden="true">
      <div className="mnu-bg-top">
        <span className="mnu-bg-gear">⚙</span>
        <span className="mnu-bg-today">TODAY ↗</span>
      </div>
      <div className="mnu-bg-h">Good run.</div>
      <div className="mnu-bg-sub">— leave the day a memo.</div>
      <div className="mnu-bg-cta">Link a run ↗</div>
    </div>
  );
}

function AppMenu({ onClose = () => {}, onSelect = () => {}, onSignOut = () => {} }) {
  return (
    <div className="mnu-stage is-open">
      <style>{MENU_CSS}</style>

      {/* dimmed app peeking from the right */}
      <MenuBackdrop />
      <div className="mnu-scrim" onClick={onClose} />

      <div className="mnu-panel" role="dialog" aria-label="Menu">
        {/* masthead */}
        <div className="mnu-head">
          <div className="mnu-toprow">
            <div className="mnu-wordmark">
              post<br />run<br /><span>drip</span>
            </div>
            <button className="mnu-close" onClick={onClose} aria-label="Close menu">✕</button>
          </div>

          <div className="mnu-platerow">
            <span className="mnu-plate">Menu · Index</span>
            <span className="mnu-plate">07 destinations</span>
          </div>

          <div className="mnu-identity">
            <div className="mnu-idblock">
              <div className="mnu-name">Alex Chen.</div>
              <div className="mnu-email">alex@postrundrip.com</div>
            </div>
            <span className="mnu-pro">Pro</span>
          </div>
        </div>

        {/* numbered index */}
        <div className="mnu-nav">
          {MENU_GROUPS.map((g) => (
            <div className="mnu-group" key={g.head}>
              <div className="mnu-grouphead">
                <span className="lbl">{g.head}</span>
                <span className="ln" />
              </div>
              {g.items.map((it) => (
                <div className="mnu-item" key={it.id} onClick={() => onSelect(it.id)}>
                  <span className="mnu-num">{it.n}</span>
                  <div>
                    <div className="mnu-label">{it.label}</div>
                    <div className="mnu-hint">{it.hint}</div>
                  </div>
                  <span className="mnu-arrow">↗</span>
                </div>
              ))}
            </div>
          ))}
        </div>

        {/* footer */}
        <div className="mnu-foot">
          <span className="mnu-signout" onClick={onSignOut}>Sign out</span>
          <span className="mnu-build">v1.0.0 · Build 042 · May 2026</span>
        </div>
      </div>
    </div>
  );
}

window.AppMenu = AppMenu;

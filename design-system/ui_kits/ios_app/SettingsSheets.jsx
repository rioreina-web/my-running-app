// Post Run Drip · iOS UI kit · Phase 4 — Settings / Profile / Goals / Backup / Export
//
// AppSidebar          — slide-in menu (hamburger in top-left of any screen)
// SettingsScreen      — preferences sheet (account, coaching, training, data)
// AthleteProfileScreen— derived athlete profile (volume / pace / injury / etc.)
// GoalsScreen         — active and completed goals
// BackupScreen        — export everything as a JSON backup
// ExportScreen        — export training logs as CSV (with date range + options)

const SETTINGS_CSS = `
/* ── App menu · editorial index (brand rebrand) ──────────────────────── */
.mnu-root { display: contents; }
.mnu-scrim {
  position: absolute; inset: 0; z-index: 40;
  background: rgba(26, 24, 21, 0.46);
  opacity: 0; pointer-events: none;
  transition: opacity .28s ease-out;
}
.mnu-root.is-open .mnu-scrim { opacity: 1; pointer-events: auto; }
.mnu-panel {
  position: absolute; top: 0; bottom: 0; left: 0; z-index: 41;
  width: 85%;
  background: var(--paper);
  box-shadow: 2px 0 28px rgba(0,0,0,0.22);
  display: flex; flex-direction: column;
  transform: translateX(-101%);
  transition: transform .34s cubic-bezier(0.22, 1, 0.36, 1);
}
.mnu-root.is-open .mnu-panel { transform: translateX(0); }

/* masthead */
.mnu-head { padding: 16px 22px 14px 24px; }
.mnu-toprow { display: flex; align-items: flex-start; justify-content: space-between; }
.mnu-wordmark {
  font-family: var(--font-display); font-weight: 800; font-size: 15px;
  line-height: 0.92; letter-spacing: -0.01em; color: var(--ink); text-transform: lowercase;
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
.mnu-platerow { display: flex; align-items: baseline; justify-content: space-between; margin-top: 18px; }
.mnu-plate {
  font-family: var(--font-mono); font-size: 10px; font-weight: 500;
  letter-spacing: 0.14em; text-transform: uppercase; color: var(--ink-3); white-space: nowrap;
}
.mnu-identity { margin-top: 12px; display: flex; align-items: flex-end; justify-content: space-between; gap: 12px; }
.mnu-idblock { min-width: 0; }
.mnu-name {
  font-family: var(--font-display); font-weight: 700; font-size: 28px;
  line-height: 1; letter-spacing: -0.015em; color: var(--ink); white-space: nowrap;
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

/* numbered index */
.mnu-nav { flex: 1; overflow-y: auto; padding: 4px 0 8px; }
.mnu-nav::-webkit-scrollbar { width: 0; }
.mnu-group { padding: 0 24px; }
.mnu-grouphead { display: flex; align-items: center; gap: 10px; padding: 16px 0 3px; }
.mnu-grouphead .lbl {
  font-family: var(--font-mono); font-size: 10px; font-weight: 500;
  letter-spacing: 0.16em; text-transform: uppercase; color: var(--ink-2);
}
.mnu-grouphead .ln { flex: 1; height: 1px; background: var(--rule); }
.mnu-item {
  display: grid; grid-template-columns: 30px 1fr 16px;
  align-items: baseline; column-gap: 14px;
  padding: 13px 0 12px;
  border-bottom: 1px solid var(--rule); cursor: pointer;
  transition: padding-left var(--dur-fast) var(--ease-out);
}
.mnu-item:last-child { border-bottom: none; }
.mnu-num {
  font-family: var(--font-mono); font-size: 12px; font-weight: 500;
  letter-spacing: 0.04em; color: var(--ink-3); font-variant-numeric: tabular-nums;
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

/* footer */
.mnu-foot {
  margin-top: auto; padding: 14px 24px 18px;
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

/* Settings list */
.prd-set__section {
  margin-top: 22px;
}
.prd-set__row {
  display: grid;
  grid-template-columns: 1fr auto;
  gap: 14px;
  align-items: center;
  padding: 14px 0;
  border-bottom: 1px solid var(--rule);
  cursor: pointer;
}
.prd-set__row-label {
  font-family: var(--font-display);
  font-size: 14px; font-weight: 500; color: var(--ink);
}
.prd-set__row-hint {
  font-family: var(--font-body); font-style: italic;
  font-size: 12px; color: var(--ink-3);
  display: block; margin-top: 2px;
}
.prd-set__row-value {
  font-family: var(--font-mono);
  font-size: 12px; font-weight: 500;
  letter-spacing: 0.10em; color: var(--ink-2);
  text-transform: uppercase;
}
.prd-set__row-value--coral { color: var(--coral); }

/* Profile stat tile */
.prd-prof__grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
  margin-top: 10px;
}
.prd-prof__tile {
  background: var(--card);
  padding: 12px 14px;
  border-radius: 12px;
  box-shadow: 0 2px 8px rgba(0,0,0,0.06);
}
.prd-prof__tile-label {
  font-family: var(--font-mono);
  font-size: 9px; font-weight: 500;
  letter-spacing: 0.12em; color: var(--ink-2);
  text-transform: uppercase;
}
.prd-prof__tile-value {
  font-family: var(--font-mono); font-weight: 600;
  font-size: 22px; color: var(--ink);
  font-variant-numeric: tabular-nums;
  line-height: 1;
  margin-top: 4px;
}
.prd-prof__tile-unit {
  font-family: var(--font-mono); font-size: 10px;
  color: var(--ink-2); margin-left: 3px;
}
.prd-prof__tile-sub {
  font-family: var(--font-mono); font-size: 9px;
  letter-spacing: 0.10em; color: var(--ink-3);
  margin-top: 4px;
}

/* Goal card */
.prd-goal {
  background: var(--card);
  padding: 18px;
  border-radius: 12px;
  box-shadow: 0 2px 8px rgba(0,0,0,0.06);
  margin-top: 12px;
}
.prd-goal-eyebrow {
  font-family: var(--font-mono);
  font-size: 10px; font-weight: 500;
  letter-spacing: 0.14em; color: var(--coral);
  text-transform: uppercase;
}
.prd-goal-title {
  font-family: var(--font-display);
  font-size: 22px; font-weight: 700; color: var(--ink);
  letter-spacing: -0.01em;
  margin-top: 4px;
}
.prd-goal-meta {
  font-family: var(--font-mono); font-size: 10px;
  letter-spacing: 0.10em; color: var(--ink-3);
  margin-top: 6px;
}

/* Backup data item */
.prd-bk__item {
  display: grid;
  grid-template-columns: 24px 1fr 60px;
  gap: 12px;
  padding: 14px 0;
  border-bottom: 1px solid var(--rule);
  align-items: baseline;
}
.prd-bk__item-mark {
  font-family: var(--font-mono); font-size: 10px;
  color: var(--mood-energized, #2D8A4E);
  letter-spacing: 0.10em;
}
.prd-bk__item-label {
  font-family: var(--font-display);
  font-size: 14px; font-weight: 500; color: var(--ink);
}
.prd-bk__item-hint {
  font-family: var(--font-body); font-style: italic;
  font-size: 12px; color: var(--ink-3);
  display: block; margin-top: 2px;
}
.prd-bk__item-count {
  font-family: var(--font-mono); font-size: 12px; font-weight: 600;
  color: var(--ink-2);
  text-align: right;
  font-variant-numeric: tabular-nums;
}
`;

// ---- Sidebar (editorial index) -----------------------------------------
const MENU_GROUPS = [
  {
    head: "Targets",
    items: [
      { n: "01", id: "goals",     label: "Goals",             hint: "Race & training targets." },
      { n: "02", id: "pace",      label: "Pace Chart",        hint: "Your training paces, by zone." },
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

const AppSidebar = ({ onClose, onSelect, onSignOut }) => {
  const total = MENU_GROUPS.reduce((n, g) => n + g.items.length, 0);
  return (
    <div className="mnu-root is-open">
      <style>{SETTINGS_CSS}</style>
      <div className="mnu-scrim" onClick={onClose} />
      <div className="mnu-panel" role="dialog" aria-label="Menu">
        {/* masthead */}
        <div className="mnu-head">
          <div className="mnu-toprow">
            <div className="mnu-wordmark">post<br />run<br /><span>drip</span></div>
            <button className="mnu-close" onClick={onClose} aria-label="Close menu">✕</button>
          </div>
          <div className="mnu-platerow">
            <span className="mnu-plate">Menu · Index</span>
            <span className="mnu-plate">{String(total).padStart(2, "0")} destinations</span>
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
};

// ---- Settings sheet -----------------------------------------------------
const SettingsScreen = ({ onClose }) => {
  const [checkIns, setCheckIns] = React.useState(true);
  const [smartInsights, setSmartInsights] = React.useState(true);
  const [coachMode, setCoachMode] = React.useState(false);
  const [maxHR, setMaxHR] = React.useState(180);
  const [units, setUnits] = React.useState("imperial");

  const sections = [
    {
      title: "Account",
      rows: [
        { l: "Email",              v: "alex@postrundrip.com",     hint: "Used for sign-in and weekly digests." },
        { l: "Subscription",       v: "PRO ·  $14 / MO",          hint: "Renews October 4.", coral: true },
        { l: "Connected services", v: "APPLE HEALTH ·  GARMIN",   hint: "Where your runs come from." },
      ],
    },
    {
      title: "Coaching",
      rows: [
        { l: "Coach check-ins",  v: checkIns ? "ON" : "OFF",       hint: "Coach reaches out after concerning memos.", toggle: () => setCheckIns(!checkIns), coral: checkIns },
        { l: "Smart insights",   v: smartInsights ? "ON" : "OFF",  hint: "AI pulls patterns from your journal.",      toggle: () => setSmartInsights(!smartInsights), coral: smartInsights },
        { l: "Weekly report",    v: "SUNDAY · 7 PM",               hint: "When the coach posts the weekly note." },
        { l: "Coach mode",       v: coachMode ? "ON" : "OFF",      hint: "Switch to athlete-roster view.",            toggle: () => setCoachMode(!coachMode), coral: coachMode },
      ],
    },
    {
      title: "Training",
      rows: [
        { l: "Maximum heart rate", v: maxHR + " BPM",        hint: "Used to compute HR zones." },
        { l: "Units",              v: units.toUpperCase(),   hint: "Distances and paces.", toggle: () => setUnits(units === "imperial" ? "metric" : "imperial") },
        { l: "Pace zones",         v: "DERIVED",             hint: "Computed from your last 8 weeks. Tap to recompute." },
        { l: "Long-run day",       v: "SUNDAY",              hint: "The plan anchors around this." },
      ],
    },
    {
      title: "Data",
      rows: [
        { l: "Backup",       v: "EXPORT JSON ↗", hint: "Everything in one file." },
        { l: "Export logs",  v: "EXPORT CSV ↗",  hint: "For Excel, Numbers, R, Python." },
        { l: "Privacy",      v: "READ ↗",        hint: "What we collect. What we don't." },
        { l: "Reset cache",  v: "CLEAR ↗",       hint: "Force a fresh sync from the cloud." },
      ],
    },
  ];

  return (
    <Sheet surface="SETTINGS" onClose={onClose}>
      <style>{SETTINGS_CSS}</style>
      <Eyebrow coral>PREFERENCES</Eyebrow>
      <h1 className="h-display" style={{ fontSize: 30, marginTop: 4 }}>Settings.</h1>
      <p style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13, color: "var(--ink-2)", marginTop: 4 }}>
        — every knob the app exposes. Nothing hidden in menus. —
      </p>

      {sections.map(s => (
        <div key={s.title} className="prd-set__section">
          <Eyebrow>{s.title.toUpperCase()}</Eyebrow>
          <div style={{ marginTop: 6 }}>
            {s.rows.map((r, i) => (
              <div key={i} className="prd-set__row" onClick={r.toggle}>
                <div>
                  <div className="prd-set__row-label">{r.l}</div>
                  <div className="prd-set__row-hint">{r.hint}</div>
                </div>
                <span className={"prd-set__row-value" + (r.coral ? " prd-set__row-value--coral" : "")}>
                  {r.v}
                </span>
              </div>
            ))}
          </div>
        </div>
      ))}

      <div style={{ marginTop: 28, paddingTop: 18, borderTop: "1px solid var(--rule)", textAlign: "center" }}>
        <span className="link" style={{ fontSize: 13, color: "var(--mood-injured, #B83A4A)", borderColor: "var(--mood-injured, #B83A4A)" }}>
          Sign out
        </span>
        <div style={{
          fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)",
          letterSpacing: "0.10em", textTransform: "uppercase", marginTop: 18,
        }}>
          POST RUN DRIP  ·  v1.0.0 BUILD 042
        </div>
      </div>
    </Sheet>
  );
};

// ---- Athlete profile sheet ---------------------------------------------
const AthleteProfileScreen = ({ onClose }) => (
  <Sheet surface="PROFILE · ATHLETE" onClose={onClose}>
    <style>{SETTINGS_CSS}</style>
    <Eyebrow coral>YOUR PROFILE</Eyebrow>
    <h1 className="h-display" style={{ fontSize: 30, marginTop: 4 }}>Alex.</h1>
    <div style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13, color: "var(--ink-2)", marginTop: 4 }}>
      — derived from 87 runs across 12 weeks. Updates every Sunday. —
    </div>

    <div style={{ height: 18 }} />
    <EditorialRule />

    {/* Volume */}
    <div className="prd-set__section">
      <Eyebrow>VOLUME</Eyebrow>
      <div className="prd-prof__grid">
        <div className="prd-prof__tile">
          <div className="prd-prof__tile-label">WEEKLY AVG · 12W</div>
          <div className="prd-prof__tile-value">42.6<span className="prd-prof__tile-unit">MI</span></div>
          <div className="prd-prof__tile-sub">+8% vs prior cycle</div>
        </div>
        <div className="prd-prof__tile">
          <div className="prd-prof__tile-label">LONGEST RUN</div>
          <div className="prd-prof__tile-value">20.0<span className="prd-prof__tile-unit">MI</span></div>
          <div className="prd-prof__tile-sub">APR 26 · 2:33:20</div>
        </div>
      </div>
    </div>

    {/* Pace */}
    <div className="prd-set__section">
      <Eyebrow>PACE PROFILE</Eyebrow>
      <div className="prd-prof__grid">
        <div className="prd-prof__tile">
          <div className="prd-prof__tile-label">EASY AVG</div>
          <div className="prd-prof__tile-value">7:38<span className="prd-prof__tile-unit">/ MI</span></div>
          <div className="prd-prof__tile-sub">Z2 · 138 BPM</div>
        </div>
        <div className="prd-prof__tile">
          <div className="prd-prof__tile-label">THRESHOLD</div>
          <div className="prd-prof__tile-value">5:58<span className="prd-prof__tile-unit">/ MI</span></div>
          <div className="prd-prof__tile-sub">−6s vs 4w ago</div>
        </div>
      </div>
    </div>

    {/* Performance */}
    <div className="prd-set__section">
      <Eyebrow>PERFORMANCE</Eyebrow>
      <div className="prd-prof__grid">
        <div className="prd-prof__tile">
          <div className="prd-prof__tile-label">FITNESS · 10K EQ</div>
          <div className="prd-prof__tile-value">36:48</div>
          <div className="prd-prof__tile-sub">−26s vs 4 weeks ago</div>
        </div>
        <div className="prd-prof__tile">
          <div className="prd-prof__tile-label">ANCHOR RACE</div>
          <div className="prd-prof__tile-value">37:14<span className="prd-prof__tile-unit">10K</span></div>
          <div className="prd-prof__tile-sub">APR 6 · 5 WEEKS AGO</div>
        </div>
      </div>
    </div>

    {/* Injury */}
    <div className="prd-set__section">
      <Eyebrow>INJURY RISK</Eyebrow>
      <div className="prd-prof__grid">
        <div className="prd-prof__tile">
          <div className="prd-prof__tile-label">RISK · COMPOSITE</div>
          <div className="prd-prof__tile-value" style={{ color: "var(--mood-energized, #2D8A4E)" }}>2.4<span className="prd-prof__tile-unit">/ 10</span></div>
          <div className="prd-prof__tile-sub">LOW · 4W AVG 2.1</div>
        </div>
        <div className="prd-prof__tile">
          <div className="prd-prof__tile-label">ACTIVE ACHES</div>
          <div className="prd-prof__tile-value">2</div>
          <div className="prd-prof__tile-sub">KNEE · ACHILLES</div>
        </div>
      </div>
    </div>

    {/* Recovery + Preferences */}
    <div className="prd-set__section">
      <Eyebrow>RECOVERY  ·  PREFERENCES</Eyebrow>
      <div className="prd-set__row">
        <div>
          <div className="prd-set__row-label">Average sleep · 14d</div>
          <div className="prd-set__row-hint">Synced from Apple Health.</div>
        </div>
        <span className="prd-set__row-value">7H 42M</span>
      </div>
      <div className="prd-set__row">
        <div>
          <div className="prd-set__row-label">Resting HR · 14d</div>
          <div className="prd-set__row-hint">Median morning HR.</div>
        </div>
        <span className="prd-set__row-value">48 BPM</span>
      </div>
      <div className="prd-set__row">
        <div>
          <div className="prd-set__row-label">Long-run day</div>
          <div className="prd-set__row-hint">Where the plan anchors weekly volume.</div>
        </div>
        <span className="prd-set__row-value">SUNDAY</span>
      </div>
      <div className="prd-set__row">
        <div>
          <div className="prd-set__row-label">Surface preference</div>
          <div className="prd-set__row-hint">Track / road / trail breakdown.</div>
        </div>
        <span className="prd-set__row-value">ROAD · 84%</span>
      </div>
    </div>

    <p style={{
      fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 12,
      color: "var(--ink-3)", lineHeight: 1.5, marginTop: 24,
    }}>
      — this profile is computed nightly. Edit a run, and it will catch up by morning. —
    </p>
  </Sheet>
);

// ---- Goals sheet -------------------------------------------------------
const ACTIVE_GOALS = [
  { id: "g1", title: "Boston Marathon · sub-2:50", subtitle: "First marathon in eight years. Sub-3:00 is the line.", date: "JUNE 24, 2026", days: 47 },
  { id: "g2", title: "10K under 36:00",            subtitle: "Tune-up race in the build. Anchors the pace ladder.", date: "MAY 30, 2026", days: 22 },
];
const COMPLETED_GOALS = [
  { id: "c1", title: "Half marathon · 1:21:48",    subtitle: "April 6 · Brooklyn Half. Hit the target.",           date: "APR 6, 2026" },
  { id: "c2", title: "Run six days a week, March", subtitle: "31 / 31 runs. The streak that started this build.", date: "MAR 31, 2026" },
];

const GoalsScreen = ({ onClose, onAddGoal }) => (
  <Sheet
    surface="GOALS · ACTIVE"
    onClose={onClose}
    action={onAddGoal}
    actionLabel="+ Add ↗"
  >
    <style>{SETTINGS_CSS}</style>
    <Eyebrow coral>GOALS</Eyebrow>
    <h1 className="h-display" style={{ fontSize: 30, marginTop: 4 }}>What you're chasing.</h1>
    <p style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13, color: "var(--ink-2)", marginTop: 4 }}>
      — kept short. Two is the right number. —
    </p>

    <div className="prd-set__section">
      <Eyebrow>ACTIVE  ·  {ACTIVE_GOALS.length}</Eyebrow>
      {ACTIVE_GOALS.map(g => (
        <div key={g.id} className="prd-goal">
          <div className="prd-goal-eyebrow">{g.days} DAYS OUT</div>
          <div className="prd-goal-title">{g.title}</div>
          <p style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13, color: "var(--ink-2)", margin: "6px 0 0 0", lineHeight: 1.5 }}>
            {g.subtitle}
          </p>
          <div className="prd-goal-meta">{g.date}  ·  ON TRACK</div>
        </div>
      ))}
    </div>

    <div className="prd-set__section">
      <Eyebrow>COMPLETED  ·  {COMPLETED_GOALS.length}</Eyebrow>
      {COMPLETED_GOALS.map(g => (
        <div key={g.id} className="prd-set__row">
          <div>
            <div className="prd-set__row-label">{g.title}</div>
            <div className="prd-set__row-hint">{g.subtitle}</div>
          </div>
          <span className="prd-set__row-value" style={{ color: "var(--mood-energized, #2D8A4E)" }}>
            DONE ✓
          </span>
        </div>
      ))}
    </div>
  </Sheet>
);

// ---- Backup sheet ------------------------------------------------------
const BackupScreen = ({ onClose }) => (
  <Sheet surface="DATA · BACKUP" onClose={onClose}>
    <style>{SETTINGS_CSS}</style>
    <Eyebrow coral>YOUR DATA</Eyebrow>
    <h1 className="h-display" style={{ fontSize: 30, marginTop: 4 }}>Back everything up.</h1>
    <p style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13, color: "var(--ink-2)", marginTop: 4 }}>
      — one JSON file with everything. Yours to keep. —
    </p>

    <div className="prd-set__section">
      <Eyebrow>INCLUDED  ·  7 COLLECTIONS</Eyebrow>
      <div style={{ marginTop: 4 }}>
        {[
          { l: "Training logs",  hint: "Voice memos, transcripts, AI summaries.", count: "342" },
          { l: "Training plans", hint: "Active plan + history of past plans.",    count: "4"   },
          { l: "Goals",          hint: "Active and completed.",                   count: "12"  },
          { l: "Injuries",       hint: "Aches and resolutions.",                  count: "8"   },
          { l: "Fitness snaps",  hint: "Weekly fitness predictor results.",       count: "12"  },
          { l: "Biomechanics",   hint: "Form-check uploads + analyses.",          count: "3"   },
          { l: "Coach threads",  hint: "Every conversation with the AI coach.",   count: "47"  },
        ].map((b, i) => (
          <div key={i} className="prd-bk__item">
            <span className="prd-bk__item-mark">✓</span>
            <div>
              <span className="prd-bk__item-label">{b.l}</span>
              <span className="prd-bk__item-hint">{b.hint}</span>
            </div>
            <span className="prd-bk__item-count">{b.count}</span>
          </div>
        ))}
      </div>
    </div>

    <button className="btn btn--primary" style={{ marginTop: 22 }}>
      Export backup ↗
    </button>
    <p style={{
      fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 12,
      color: "var(--ink-3)", lineHeight: 1.5, marginTop: 12, textAlign: "center",
    }}>
      — last export: April 3, 2026 · 14.2 MB. —
    </p>
  </Sheet>
);

// ---- Export logs sheet -------------------------------------------------
const ExportScreen = ({ onClose }) => {
  const [range, setRange] = React.useState("month");
  const [format, setFormat] = React.useState("csv");
  const [includeVoice, setIncludeVoice] = React.useState(false);
  const [includeCoach, setIncludeCoach] = React.useState(true);

  return (
    <Sheet surface="DATA · EXPORT LOGS" onClose={onClose}>
      <style>{SETTINGS_CSS}</style>
      <Eyebrow coral>EXPORT</Eyebrow>
      <h1 className="h-display" style={{ fontSize: 30, marginTop: 4 }}>Logs to a spreadsheet.</h1>
      <p style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13, color: "var(--ink-2)", marginTop: 4 }}>
        — for analysis in Excel, Numbers, R, Python. Yours to keep. —
      </p>

      <div className="prd-set__section">
        <Eyebrow>DATE RANGE</Eyebrow>
        <div className="prd-chip-cluster" style={{ marginTop: 6 }}>
          {[
            { v: "week",  l: "LAST 7 DAYS" },
            { v: "month", l: "LAST 30 DAYS" },
            { v: "year",  l: "LAST YEAR" },
            { v: "all",   l: "ALL TIME" },
          ].map(r => (
            <span key={r.v} className={"prd-chip" + (range === r.v ? " is-active" : "")} onClick={() => setRange(r.v)}>
              {r.l}
            </span>
          ))}
        </div>
      </div>

      <div className="prd-set__section">
        <Eyebrow>FORMAT</Eyebrow>
        <div className="prd-chip-cluster" style={{ marginTop: 6 }}>
          {[
            { v: "csv",  l: "CSV" },
            { v: "tsv",  l: "TSV" },
            { v: "json", l: "JSON" },
            { v: "fit",  l: "FIT" },
          ].map(f => (
            <span key={f.v} className={"prd-chip" + (format === f.v ? " is-active" : "")} onClick={() => setFormat(f.v)}>
              {f.l}
            </span>
          ))}
        </div>
      </div>

      <div className="prd-set__section">
        <Eyebrow>INCLUDE</Eyebrow>
        <div className="prd-set__row" onClick={() => setIncludeVoice(!includeVoice)}>
          <div>
            <div className="prd-set__row-label">Voice memo transcripts</div>
            <div className="prd-set__row-hint">Cleaned and raw, side by side.</div>
          </div>
          <span className={"prd-set__row-value" + (includeVoice ? " prd-set__row-value--coral" : "")}>
            {includeVoice ? "ON" : "OFF"}
          </span>
        </div>
        <div className="prd-set__row" onClick={() => setIncludeCoach(!includeCoach)}>
          <div>
            <div className="prd-set__row-label">Coach insights</div>
            <div className="prd-set__row-hint">The note attached to each run.</div>
          </div>
          <span className={"prd-set__row-value" + (includeCoach ? " prd-set__row-value--coral" : "")}>
            {includeCoach ? "ON" : "OFF"}
          </span>
        </div>
      </div>

      <button className="btn btn--primary" style={{ marginTop: 22 }}>
        Export {format.toUpperCase()} ↗
      </button>
      <p style={{
        fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 12,
        color: "var(--ink-3)", lineHeight: 1.5, marginTop: 12, textAlign: "center",
      }}>
        — about 42 rows. Estimated 9 KB. —
      </p>
    </Sheet>
  );
};

window.AppSidebar = AppSidebar;
window.SettingsScreen = SettingsScreen;
window.AthleteProfileScreen = AthleteProfileScreen;
window.GoalsScreen = GoalsScreen;
window.BackupScreen = BackupScreen;
window.ExportScreen = ExportScreen;

// ════════════════════════════════════════════════════════════════════════
// Menu destinations that didn't exist in the kit yet — Pace Chart,
// Fitness Predictor, Content Library. Editorial language: hairline tables,
// mono tabular numerals, one coral hit per surface.
// ════════════════════════════════════════════════════════════════════════

const MENU_DEST_CSS = `
.prd-mdest__ladder { border-top: 1px solid var(--rule); margin-top: 14px; }
.prd-mdest__zone {
  display: grid; grid-template-columns: 14px 1fr auto;
  align-items: baseline; gap: 12px;
  padding: 13px 0; border-bottom: 1px solid var(--rule);
}
.prd-mdest__ztick { width: 8px; height: 8px; border-radius: 999px; align-self: center; }
.prd-mdest__zname {
  font-family: var(--font-display); font-weight: 600; font-size: 16px; color: var(--ink);
}
.prd-mdest__zsub {
  font-family: var(--font-body); font-style: italic; font-size: 12px;
  color: var(--ink-3); margin-top: 1px;
}
.prd-mdest__zpace {
  font-family: var(--font-mono); font-weight: 600; font-size: 15px; color: var(--ink);
  font-variant-numeric: tabular-nums; white-space: nowrap;
}
.prd-mdest__zpace span { font-size: 10px; color: var(--ink-3); margin-left: 2px; }

.prd-mdest__predgrid {
  display: grid; grid-template-columns: 1fr 1fr; gap: 1px;
  background: var(--rule); border: 1px solid var(--rule); margin-top: 16px;
}
.prd-mdest__pred { background: var(--paper); padding: 16px 14px; }
.prd-mdest__pred-l {
  font-family: var(--font-mono); font-size: 10px; letter-spacing: 0.12em;
  text-transform: uppercase; color: var(--ink-2);
}
.prd-mdest__pred-v {
  font-family: var(--font-mono); font-weight: 600; font-size: 26px; color: var(--ink);
  font-variant-numeric: tabular-nums; line-height: 1; margin-top: 8px;
}
.prd-mdest__pred-d {
  font-family: var(--font-mono); font-size: 10px; color: var(--ink-3);
  margin-top: 6px; letter-spacing: 0.06em;
}
.prd-mdest__pred-d.up { color: var(--mood-energized); }

.prd-mdest__item {
  display: grid; grid-template-columns: 1fr auto; gap: 12px; align-items: baseline;
  padding: 14px 0; border-bottom: 1px solid var(--rule); cursor: pointer;
}
.prd-mdest__item-ey {
  font-family: var(--font-mono); font-size: 9px; letter-spacing: 0.12em;
  text-transform: uppercase; color: var(--ink-3);
}
.prd-mdest__item-t {
  font-family: var(--font-display); font-weight: 600; font-size: 17px;
  color: var(--ink); margin-top: 3px; letter-spacing: -0.01em;
}
.prd-mdest__item-m {
  font-family: var(--font-mono); font-size: 11px; color: var(--ink-3);
  font-variant-numeric: tabular-nums; white-space: nowrap; align-self: center;
}
`;

const PACE_ZONES = [
  { c: "#4A9E6B", name: "Recovery",  sub: "shake-out, between hard days", pace: "9:10–9:50" },
  { c: "#2D8A4E", name: "Easy",      sub: "the bread-and-butter aerobic mile", pace: "8:05–8:45" },
  { c: "#C4873A", name: "Steady",    sub: "comfortably-hard long-run finish", pace: "7:25–7:50" },
  { c: "#D4592A", name: "Marathon",  sub: "goal race pace", pace: "7:05–7:15", coral: true },
  { c: "#C45A3A", name: "Threshold", sub: "tempo / lactate turnpoint", pace: "6:35–6:50" },
  { c: "#6B4A8A", name: "Interval",  sub: "VO₂max repeats, 3–5 min", pace: "5:55–6:10" },
];

const PaceChartScreen = ({ onClose }) => (
  <Sheet surface="TARGETS · PACE CHART" onClose={onClose}>
    <style>{SETTINGS_CSS}</style>
    <style>{MENU_DEST_CSS}</style>
    <Eyebrow coral>TRAINING PACES</Eyebrow>
    <h1 className="h-display" style={{ fontSize: 30, marginTop: 4 }}>Pace chart.</h1>
    <p style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13, color: "var(--ink-2)", marginTop: 4 }}>
      — derived from your last 8 weeks. Six zones, one race target. —
    </p>
    <div className="prd-mdest__ladder">
      {PACE_ZONES.map(z => (
        <div className="prd-mdest__zone" key={z.name}>
          <span className="prd-mdest__ztick" style={{ background: z.c }} />
          <div>
            <div className="prd-mdest__zname">{z.name}</div>
            <div className="prd-mdest__zsub">{z.sub}</div>
          </div>
          <div className="prd-mdest__zpace" style={z.coral ? { color: "var(--coral)" } : null}>
            {z.pace}<span>/mi</span>
          </div>
        </div>
      ))}
    </div>
  </Sheet>
);

const FitnessPredictorScreen = ({ onClose }) => (
  <Sheet surface="TARGETS · FITNESS PREDICTOR" onClose={onClose}>
    <style>{SETTINGS_CSS}</style>
    <style>{MENU_DEST_CSS}</style>
    <Eyebrow coral>RACE-TIME PREDICTIONS</Eyebrow>
    <h1 className="h-display" style={{ fontSize: 30, marginTop: 4 }}>Where you stand.</h1>
    <p style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13, color: "var(--ink-2)", marginTop: 4 }}>
      — modeled from current fitness. Updated this morning. —
    </p>
    <div className="prd-mdest__predgrid">
      {[
        { l: "5K",       v: "20:14", d: "−0:18 vs last", up: true },
        { l: "10K",      v: "42:06", d: "−0:31 vs last", up: true },
        { l: "Half",     v: "1:33:40", d: "−1:12 vs last", up: true },
        { l: "Marathon", v: "3:18:22", d: "goal: 3:15", up: false },
      ].map(p => (
        <div className="prd-mdest__pred" key={p.l}>
          <div className="prd-mdest__pred-l">{p.l}</div>
          <div className="prd-mdest__pred-v">{p.v}</div>
          <div className={"prd-mdest__pred-d" + (p.up ? " up" : "")}>{p.d}</div>
        </div>
      ))}
    </div>
    <p style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 12, color: "var(--ink-3)", lineHeight: 1.5, marginTop: 16, textAlign: "center" }}>
      — confidence: high. Based on 32 quality sessions. —
    </p>
  </Sheet>
);

const LIBRARY_ITEMS = [
  { ey: "FILM · 8 MIN",     t: "The easy-day discipline",       m: "WATCHED" },
  { ey: "DRILL · 12 MIN",   t: "Strides & form sprints",        m: "NEW" },
  { ey: "READING · 6 MIN",  t: "Why negative splits work",      m: "—" },
  { ey: "FILM · 14 MIN",    t: "Marathon fueling, start to line", m: "NEW" },
  { ey: "DRILL · 9 MIN",    t: "Hip mobility for runners",      m: "—" },
];

const ContentLibraryScreen = ({ onClose }) => (
  <Sheet surface="LIBRARY · CONTENT" onClose={onClose}>
    <style>{SETTINGS_CSS}</style>
    <style>{MENU_DEST_CSS}</style>
    <Eyebrow coral>FILMS · DRILLS · READING</Eyebrow>
    <h1 className="h-display" style={{ fontSize: 30, marginTop: 4 }}>The library.</h1>
    <p style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13, color: "var(--ink-2)", marginTop: 4 }}>
      — short, practical, made for the in-between days. —
    </p>
    <div style={{ marginTop: 14, borderTop: "1px solid var(--rule)" }}>
      {LIBRARY_ITEMS.map(it => (
        <div className="prd-mdest__item" key={it.t}>
          <div>
            <div className="prd-mdest__item-ey">{it.ey}</div>
            <div className="prd-mdest__item-t">{it.t}</div>
          </div>
          <span className="prd-mdest__item-m" style={it.m === "NEW" ? { color: "var(--coral)" } : null}>{it.m}</span>
        </div>
      ))}
    </div>
  </Sheet>
);

window.PaceChartScreen = PaceChartScreen;
window.FitnessPredictorScreen = FitnessPredictorScreen;
window.ContentLibraryScreen = ContentLibraryScreen;

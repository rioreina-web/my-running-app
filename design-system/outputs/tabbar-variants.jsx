// Post Run Drip · Tab bar — 6 variant components
// Each variant accepts { active, onChange, roster, meta? } and renders
// a bottom tab bar sized for a 390pt-wide iPhone frame.
//
// Roster is an array of { id, label, meta? }.
// `meta` map (id → string) is read by V6 only.

// ─── Shared styles (injected once) ───────────────────────────────────
(function injectTabBarStyles(){
  if (document.getElementById('tabbar-variant-styles')) return;
  const css = `
    .tbv { background: var(--paper); display: grid; grid-template-columns: repeat(var(--n,5), 1fr);
      position: relative; user-select: none; }
    .tbv__tab { display: flex; flex-direction: column; align-items: center; cursor: pointer;
      padding: 10px 0 12px; gap: 7px; position: relative; }
    .tbv__lbl { font-family: var(--font-mono); font-size: 10px; letter-spacing: 0.12em;
      color: var(--ink-2); text-transform: uppercase; transition: color 150ms var(--ease-out),
      font-weight 150ms var(--ease-out), letter-spacing 220ms var(--ease-out); }

    /* ── V1 · Canonical ─────────────────────────────────────────── */
    .tbv-canonical { border-top: 1px solid var(--rule); }
    .tbv-canonical .tbv__dot { width: 6px; height: 6px; border-radius: 999px;
      background: transparent; border: 1.5px solid var(--ink-3); box-sizing: border-box;
      transition: background 150ms var(--ease-out), border-color 150ms var(--ease-out),
                  transform 150ms var(--ease-out); }
    .tbv-canonical .is-active .tbv__dot { background: var(--coral); border-color: var(--coral); }
    .tbv-canonical .is-active .tbv__lbl { color: var(--ink); font-weight: 600; }
    .tbv-canonical .tbv__tab:active .tbv__dot { transform: scale(0.7); }

    /* ── V2 · Folio (magazine page-number style) ────────────────── */
    .tbv-folio { border-top: 1px solid var(--rule); padding-top: 4px; }
    .tbv-folio .tbv__tab { gap: 4px; padding-top: 8px; }
    .tbv-folio .tbv__folio { font-family: var(--font-mono); font-size: 9px;
      letter-spacing: 0.14em; color: var(--ink-3); text-transform: uppercase;
      font-variant-numeric: tabular-nums; transition: color 150ms var(--ease-out); }
    .tbv-folio .is-active .tbv__folio { color: var(--coral); }
    .tbv-folio .is-active .tbv__lbl { color: var(--ink); font-weight: 600; }
    .tbv-folio .tbv__mark { position: absolute; top: -1px; left: 50%;
      transform: translateX(-50%); width: 18px; height: 1px; background: var(--coral);
      opacity: 0; transition: opacity 150ms var(--ease-out); }
    .tbv-folio .is-active .tbv__mark { opacity: 1; }

    /* ── V3 · Underline ─────────────────────────────────────────── */
    .tbv-underline { border-top: 1px solid var(--rule); padding-top: 4px; }
    .tbv-underline .tbv__tab { padding: 14px 0 12px; gap: 0; }
    .tbv-underline .is-active .tbv__lbl { color: var(--ink); font-weight: 600; }
    .tbv-underline .tbv__rule { position: absolute; bottom: 6px; left: 50%;
      transform: translateX(-50%); width: 28px; height: 1px; background: var(--coral);
      opacity: 0; transition: opacity 150ms var(--ease-out), width 220ms var(--ease-out); }
    .tbv-underline .is-active .tbv__rule { opacity: 1; }

    /* ── V4 · Slider (top-rule travelling cursor) ──────────────── */
    .tbv-slider { padding-top: 0; position: relative; }
    .tbv-slider::before { content: ""; position: absolute; top: 0; left: 0; right: 0;
      height: 1px; background: var(--rule); }
    .tbv-slider .tbv__cursor { position: absolute; top: 0; height: 2px;
      background: var(--coral); border-radius: 999px;
      transition: left var(--tbv-dur, 260ms) var(--ease-out),
                  width var(--tbv-dur, 260ms) var(--ease-out); }
    .tbv-slider .tbv__tab { padding: 14px 0 12px; }
    .tbv-slider .is-active .tbv__lbl { color: var(--ink); font-weight: 600; }

    /* ── V5 · Serif edition (Crimson Pro italic, mixed-case) ───── */
    .tbv-serif { border-top: 1px solid var(--rule); padding-top: 6px; }
    .tbv-serif .tbv__tab { gap: 4px; padding: 10px 0 14px; }
    .tbv-serif .tbv__dot { width: 4px; height: 4px; border-radius: 999px;
      background: transparent; transition: background 150ms var(--ease-out); }
    .tbv-serif .is-active .tbv__dot { background: var(--coral); }
    .tbv-serif .tbv__lbl-serif { font-family: var(--font-display); font-style: italic;
      font-weight: 500; font-size: 17px; letter-spacing: -0.005em; color: var(--ink-2);
      text-transform: none; line-height: 1; transition: all 150ms var(--ease-out); }
    .tbv-serif .is-active .tbv__lbl-serif { color: var(--ink); font-weight: 700;
      font-style: normal; }

    /* ── V6 · Meta (active grows with contextual sub-eyebrow) ──── */
    .tbv-meta { border-top: 1px solid var(--rule); padding-top: 4px;
      grid-template-columns: var(--meta-cols, 1fr 1fr 1fr 1fr 1fr); }
    .tbv-meta .tbv__tab { gap: 5px; padding: 10px 0 12px; min-width: 0; }
    .tbv-meta .tbv__dot { width: 5px; height: 5px; border-radius: 999px;
      background: transparent; border: 1.5px solid var(--ink-3); box-sizing: border-box;
      transition: background 150ms var(--ease-out), border-color 150ms var(--ease-out); }
    .tbv-meta .is-active .tbv__dot { background: var(--coral); border-color: var(--coral); }
    .tbv-meta .is-active .tbv__lbl { color: var(--ink); font-weight: 600; }
    .tbv-meta .tbv__meta { font-family: var(--font-mono); font-size: 8.5px;
      letter-spacing: 0.10em; color: var(--coral); text-transform: uppercase;
      opacity: 0; height: 0; overflow: hidden; transition: opacity 200ms var(--ease-out); }
    .tbv-meta .is-active .tbv__meta { opacity: 1; height: 10px; margin-top: -1px; }

    /* ── Press feedback (all variants) ──────────────────────────── */
    .tbv__tab:active { transform: scale(0.97); }
  `;
  const s = document.createElement('style');
  s.id = 'tabbar-variant-styles';
  s.textContent = css;
  document.head.appendChild(s);
})();

// ─── Default rosters ─────────────────────────────────────────────────
const ROSTER_CURRENT = [
  { id: 'log',     label: 'LOG' },
  { id: 'train',   label: 'TRAINING' },
  { id: 'trends',  label: 'TRENDS' },
  { id: 'coach',   label: 'COACH' },
  { id: 'plan',    label: 'PLAN' },
];
const ROSTER_SHORT = [
  { id: 'log',     label: 'LOG' },
  { id: 'train',   label: 'TRAIN' },
  { id: 'trends',  label: 'TRENDS' },
  { id: 'coach',   label: 'COACH' },
  { id: 'plan',    label: 'PLAN' },
];
const ROSTER_SPEC = [
  { id: 'log',     label: 'LOG' },
  { id: 'train',   label: 'TRAIN' },
  { id: 'trends',  label: 'TRENDS' },
  { id: 'coach',   label: 'COACH' },
  { id: 'runs',    label: 'RUNS' },
];
const ROSTER_SERIF_CURRENT = [
  { id: 'log',     label: 'Log' },
  { id: 'train',   label: 'Training' },
  { id: 'trends',  label: 'Trends' },
  { id: 'coach',   label: 'Coach' },
  { id: 'plan',    label: 'Plan' },
];
const ROSTER_SERIF_SPEC = [
  { id: 'log',     label: 'Log' },
  { id: 'train',   label: 'Train' },
  { id: 'trends',  label: 'Trends' },
  { id: 'coach',   label: 'Coach' },
  { id: 'runs',    label: 'Runs' },
];

// Default meta per tab — used by V6
const META_DEFAULT = {
  log:    'today',
  train:  '8 × 400m',
  trends: '4w · up',
  coach:  '1 new',
  plan:   'wk 12 / 16',
  runs:   '4 this wk',
};

// ─── V1 · Canonical ──────────────────────────────────────────────────
const TabBarV1Canonical = ({ active, onChange, roster = ROSTER_SHORT }) => (
  <div className="tbv tbv-canonical" style={{ '--n': roster.length }}>
    {roster.map(t => (
      <div key={t.id} className={'tbv__tab' + (active === t.id ? ' is-active' : '')}
        onClick={() => onChange && onChange(t.id)}>
        <div className="tbv__dot" />
        <div className="tbv__lbl">{t.label}</div>
      </div>
    ))}
  </div>
);

// ─── V2 · Folio ──────────────────────────────────────────────────────
const TabBarV2Folio = ({ active, onChange, roster = ROSTER_SHORT }) => (
  <div className="tbv tbv-folio" style={{ '--n': roster.length }}>
    {roster.map((t, i) => (
      <div key={t.id} className={'tbv__tab' + (active === t.id ? ' is-active' : '')}
        onClick={() => onChange && onChange(t.id)}>
        <div className="tbv__mark" />
        <div className="tbv__folio">p.{String(i + 1).padStart(2, '0')}</div>
        <div className="tbv__lbl">{t.label}</div>
      </div>
    ))}
  </div>
);

// ─── V3 · Underline ──────────────────────────────────────────────────
const TabBarV3Underline = ({ active, onChange, roster = ROSTER_SHORT }) => (
  <div className="tbv tbv-underline" style={{ '--n': roster.length }}>
    {roster.map(t => (
      <div key={t.id} className={'tbv__tab' + (active === t.id ? ' is-active' : '')}
        onClick={() => onChange && onChange(t.id)}>
        <div className="tbv__lbl">{t.label}</div>
        <div className="tbv__rule" />
      </div>
    ))}
  </div>
);

// ─── V4 · Slider ─────────────────────────────────────────────────────
const TabBarV4Slider = ({ active, onChange, roster = ROSTER_SHORT, duration = 260 }) => {
  const idx = Math.max(0, roster.findIndex(t => t.id === active));
  const n = roster.length;
  const segW = 100 / n;
  // Cursor 60% of a column, centred
  const cursorW = segW * 0.5;
  const cursorL = segW * idx + (segW - cursorW) / 2;
  return (
    <div className="tbv tbv-slider" style={{ '--n': n, '--tbv-dur': duration + 'ms' }}>
      <div className="tbv__cursor" style={{ left: cursorL + '%', width: cursorW + '%' }} />
      {roster.map(t => (
        <div key={t.id} className={'tbv__tab' + (active === t.id ? ' is-active' : '')}
          onClick={() => onChange && onChange(t.id)}>
          <div className="tbv__lbl">{t.label}</div>
        </div>
      ))}
    </div>
  );
};

// ─── V5 · Serif edition ──────────────────────────────────────────────
const TabBarV5Serif = ({ active, onChange, roster = ROSTER_SERIF_CURRENT }) => (
  <div className="tbv tbv-serif" style={{ '--n': roster.length }}>
    {roster.map(t => (
      <div key={t.id} className={'tbv__tab' + (active === t.id ? ' is-active' : '')}
        onClick={() => onChange && onChange(t.id)}>
        <div className="tbv__dot" />
        <div className="tbv__lbl-serif">{t.label}</div>
      </div>
    ))}
  </div>
);

// ─── V6 · Meta (contextual sub-eyebrow on active) ────────────────────
const TabBarV6Meta = ({ active, onChange, roster = ROSTER_SHORT, meta = META_DEFAULT }) => (
  <div className="tbv tbv-meta" style={{ '--n': roster.length }}>
    {roster.map(t => (
      <div key={t.id} className={'tbv__tab' + (active === t.id ? ' is-active' : '')}
        onClick={() => onChange && onChange(t.id)}>
        <div className="tbv__dot" />
        <div className="tbv__lbl">{t.label}</div>
        <div className="tbv__meta">{(meta[t.id] || '').toUpperCase()}</div>
      </div>
    ))}
  </div>
);

// ─── Variant registry (for the prototype switcher) ───────────────────
const TAB_VARIANTS = {
  canonical: { id: 'canonical', label: 'V1 · Canonical',  Comp: TabBarV1Canonical, blurb: 'Dot above uppercase mono label · the spec'  },
  folio:     { id: 'folio',     label: 'V2 · Folio',      Comp: TabBarV2Folio,     blurb: 'Magazine page-numerals — p.01, p.02 …'      },
  underline: { id: 'underline', label: 'V3 · Underline',  Comp: TabBarV3Underline, blurb: 'Type-only · coral hairline marks active'    },
  slider:    { id: 'slider',    label: 'V4 · Slider',     Comp: TabBarV4Slider,    blurb: 'Coral segment travels along the top rule'   },
  serif:     { id: 'serif',     label: 'V5 · Serif',      Comp: TabBarV5Serif,     blurb: 'Crimson Pro italic · most magazine-y'       },
  meta:      { id: 'meta',      label: 'V6 · Meta',       Comp: TabBarV6Meta,      blurb: 'Active grows with a contextual sub-eyebrow' },
};

Object.assign(window, {
  TabBarV1Canonical, TabBarV2Folio, TabBarV3Underline,
  TabBarV4Slider, TabBarV5Serif, TabBarV6Meta,
  TAB_VARIANTS, ROSTER_CURRENT, ROSTER_SHORT, ROSTER_SPEC,
  ROSTER_SERIF_CURRENT, ROSTER_SERIF_SPEC, META_DEFAULT,
});

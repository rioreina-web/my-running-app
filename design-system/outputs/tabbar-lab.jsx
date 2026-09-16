// Post Run Drip · Tab Bar Lab — assembled design canvas + interactive prototype
// Loads:
//   - design canvas (DesignCanvas, DCSection, DCArtboard)
//   - tweaks panel (TweaksPanel, useTweaks, TweakRadio…)
//   - iOS frame (IOSDevice)
//   - tab bar variants (TAB_VARIANTS, rosters)
//   - Post Run Drip primitives (Eyebrow, MoodPill, StatTile)

// ─── Mini-screen used as in-context backdrop for each variant card ─────
const MiniLogBackdrop = ({ height = 168 }) => (
  <div style={{
    background: 'var(--paper)', height, padding: '14px 22px 0',
    boxSizing: 'border-box', display: 'flex', flexDirection: 'column', gap: 10,
    overflow: 'hidden', position: 'relative',
  }}>
    {/* Top strip */}
    <div style={{
      display: 'flex', justifyContent: 'space-between',
      fontFamily: 'var(--font-mono)', fontSize: 9, letterSpacing: '0.14em',
      color: 'var(--ink-2)', textTransform: 'uppercase',
    }}>
      <span><span style={{ color: 'var(--ink)' }}>RUNNING LOG</span> — TODAY · v1</span>
      <span>WEEK 12 / 16</span>
    </div>
    {/* Title */}
    <div style={{
      fontFamily: 'var(--font-display)', fontWeight: 700, fontSize: 30,
      lineHeight: 1, color: 'var(--ink)', letterSpacing: '-0.01em',
    }}>May 21st.</div>
    {/* Sub */}
    <div style={{
      fontFamily: 'var(--font-body)', fontStyle: 'italic', fontSize: 13,
      color: 'var(--ink-2)', lineHeight: 1.4, marginTop: -2,
    }}>Easy 6 on the menu — keep heart rate sub-150.</div>
    {/* Faded gradient over the bottom so the bar reads as the focus */}
    <div style={{
      position: 'absolute', left: 0, right: 0, bottom: 0, height: 40,
      background: 'linear-gradient(to bottom, transparent, var(--paper))',
      pointerEvents: 'none',
    }} />
  </div>
);

// ─── Variant card · isolated bar with realistic hint above ──────────────
const VariantCard = ({ variantId, roster, meta, height = 240, initial = 'log' }) => {
  const [active, setActive] = React.useState(initial);
  const v = TAB_VARIANTS[variantId];
  const Bar = v.Comp;
  return (
    <div style={{
      width: 390, height, background: 'var(--paper)',
      display: 'flex', flexDirection: 'column', position: 'relative',
      boxShadow: '0 1px 0 rgba(0,0,0,0.04)', overflow: 'hidden',
    }}>
      <div style={{ flex: 1, minHeight: 0 }}>
        <MiniLogBackdrop height="100%" />
      </div>
      <Bar active={active} onChange={setActive} roster={roster} meta={meta} />
      {/* Home indicator */}
      <div style={{
        height: 22, display: 'flex', alignItems: 'center', justifyContent: 'center',
        background: 'var(--paper)',
      }}>
        <div style={{ width: 130, height: 4, borderRadius: 999, background: 'rgba(0,0,0,0.18)' }} />
      </div>
    </div>
  );
};

// ─── State card · single state callout (active/pressed/badge/disabled) ──
const StateCard = ({ title, children, height = 152, dark = false, note }) => (
  <div style={{
    width: 390, height, position: 'relative',
    background: dark ? '#1A1815' : 'var(--paper)',
    display: 'flex', flexDirection: 'column', overflow: 'hidden',
  }}>
    {/* state label, top-left */}
    <div style={{
      padding: '12px 16px 0', fontFamily: 'var(--font-mono)', fontSize: 9,
      letterSpacing: '0.14em', textTransform: 'uppercase',
      color: dark ? 'rgba(245,243,240,0.55)' : 'var(--ink-2)',
      display: 'flex', justifyContent: 'space-between',
    }}>
      <span>{title}</span>
      {note && <span style={{ color: dark ? 'rgba(245,243,240,0.40)' : 'var(--ink-3)' }}>{note}</span>}
    </div>
    <div style={{ flex: 1 }} />
    {children}
    <div style={{
      height: 22, display: 'flex', alignItems: 'center', justifyContent: 'center',
      background: dark ? '#1A1815' : 'var(--paper)',
    }}>
      <div style={{
        width: 130, height: 4, borderRadius: 999,
        background: dark ? 'rgba(245,243,240,0.25)' : 'rgba(0,0,0,0.18)',
      }} />
    </div>
  </div>
);

// ─── Dark-mode wrapper · flips a few CSS vars so the canonical bar reads
// correctly on warm-black paper. (Applied by inline overrides only.)
const darkModeVars = {
  '--paper': '#1A1815',
  '--rule': 'rgba(245,243,240,0.10)',
  '--ink': '#F5F3F0',
  '--ink-2': 'rgba(245,243,240,0.62)',
  '--ink-3': 'rgba(245,243,240,0.32)',
};

// ─── Canonical with a badge dot on Coach ─────────────────────────────
const BadgeCanonical = ({ active = 'log', onChange = () => {}, roster = window.ROSTER_SHORT,
  badgeOn = 'coach' }) => (
  <div className="tbv tbv-canonical" style={{ '--n': roster.length }}>
    {roster.map(t => (
      <div key={t.id} className={'tbv__tab' + (active === t.id ? ' is-active' : '')}
        onClick={() => onChange(t.id)} style={{ position: 'relative' }}>
        <div className="tbv__dot" />
        <div className="tbv__lbl">{t.label}</div>
        {t.id === badgeOn && (
          <div style={{
            position: 'absolute', top: 8, left: 'calc(50% + 9px)',
            width: 6, height: 6, borderRadius: 999, background: 'var(--coral)',
            boxShadow: '0 0 0 2px var(--paper)',
          }} />
        )}
      </div>
    ))}
  </div>
);

// ─── Disabled-Plan variant (Plan is greyed and not clickable) ───────
const DisabledCanonical = ({ active = 'log', onChange = () => {}, roster = window.ROSTER_SHORT,
  disabled = ['plan'] }) => (
  <div className="tbv tbv-canonical" style={{ '--n': roster.length }}>
    {roster.map(t => {
      const dis = disabled.includes(t.id);
      return (
        <div key={t.id}
          className={'tbv__tab' + (active === t.id ? ' is-active' : '')}
          onClick={() => !dis && onChange(t.id)}
          style={{ opacity: dis ? 0.32 : 1, cursor: dis ? 'default' : 'pointer' }}>
          <div className="tbv__dot" />
          <div className="tbv__lbl">{t.label}{dis && ' ·'}</div>
        </div>
      );
    })}
  </div>
);

// ─── Pressed-state demo (the LOG tab dot is mid-press, shrunk) ───────
const PressedCanonical = ({ active = 'train', pressed = 'log',
  onChange = () => {}, roster = window.ROSTER_SHORT }) => (
  <div className="tbv tbv-canonical" style={{ '--n': roster.length }}>
    {roster.map(t => (
      <div key={t.id} className={'tbv__tab' + (active === t.id ? ' is-active' : '')}
        onClick={() => onChange(t.id)}
        style={t.id === pressed ? { transform: 'scale(0.97)' } : null}>
        <div className="tbv__dot"
          style={t.id === pressed
            ? { transform: 'scale(0.65)', background: 'var(--ink-3)', borderColor: 'var(--ink-3)' }
            : null} />
        <div className="tbv__lbl">{t.label}</div>
      </div>
    ))}
  </div>
);

// ─── Interactive prototype frame ─────────────────────────────────────
const PROTOTYPE_TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "variant": "canonical",
  "roster": "current",
  "motionMs": 200,
  "dark": false,
  "showMeta": true,
  "badge": true,
  "active": "log"
}/*EDITMODE-END*/;

// Rosters are registered on window by tabbar-variants.jsx. Resolved lazily so this
// file can also be evaluated before its sibling (as the design-system bundle does).
const rosterMap = () => ({
  current: { mono: window.ROSTER_CURRENT, serif: window.ROSTER_SERIF_CURRENT, note: 'LOG · TRAINING · TRENDS · COACH · PLAN' },
  short:   { mono: window.ROSTER_SHORT,   serif: window.ROSTER_SERIF_CURRENT, note: 'LOG · TRAIN · TRENDS · COACH · PLAN' },
  spec:    { mono: window.ROSTER_SPEC,    serif: window.ROSTER_SERIF_SPEC,    note: 'LOG · TRAIN · TRENDS · COACH · RUNS' },
});

const PrototypeFrame = () => {
  const [t, setTweak] = useTweaks(PROTOTYPE_TWEAK_DEFAULTS);
  const v = TAB_VARIANTS[t.variant] || TAB_VARIANTS.canonical;
  const Bar = v.Comp;

  const MAP = rosterMap();
  const rosterPack = MAP[t.roster] || MAP.current;
  const roster = t.variant === 'serif' ? rosterPack.serif : rosterPack.mono;

  // If user picks a "spec" roster, the active id may not exist — clamp.
  React.useEffect(() => {
    if (!roster.find(r => r.id === t.active)) {
      setTweak('active', roster[0].id);
    }
  }, [roster, t.active]);

  const active = roster.find(r => r.id === t.active) ? t.active : roster[0].id;

  const paperVars = t.dark ? darkModeVars : {};

  const meta = t.showMeta ? window.META_DEFAULT : {};

  return (
    <div style={{ ...paperVars, width: 390, height: 844, position: 'relative' }}>
      <IOSDevice width={390} height={844} dark={t.dark}>
        <div style={{
          paddingTop: 62, paddingBottom: 0, height: '100%', boxSizing: 'border-box',
          display: 'flex', flexDirection: 'column',
          background: 'var(--paper)',
          ...paperVars,
        }}>
          {/* Faux screen body */}
          <div style={{ flex: 1, overflow: 'hidden', padding: '12px 24px 0',
            display: 'flex', flexDirection: 'column', gap: 14 }}>
            <PrototypeScreen tabId={active} dark={t.dark} />
          </div>
          {/* The bar */}
          <div style={paperVars}>
            <Bar
              active={active}
              onChange={(id) => setTweak('active', id)}
              roster={roster}
              meta={meta}
              duration={t.motionMs}
            />
          </div>
          {/* Home-indicator safe space */}
          <div style={{ height: 22, background: 'var(--paper)' }} />
        </div>
      </IOSDevice>

      <TweaksPanel title="Tweaks">
        <TweakSection label="Variant" />
        <TweakSelect label="Style" value={t.variant}
          options={Object.values(TAB_VARIANTS).map(v => ({ value: v.id, label: v.label }))}
          onChange={(v) => setTweak('variant', v)} />
        <div style={{ font: '10px/1.4 ui-monospace, monospace', color: 'rgba(41,38,27,.5)',
          padding: '2px 2px 4px', letterSpacing: '0.04em' }}>
          {v.blurb}
        </div>

        <TweakSection label="Roster" />
        <TweakRadio label="Names" value={t.roster}
          options={[
            { value: 'current', label: 'Current' },
            { value: 'short',   label: 'Short' },
            { value: 'spec',    label: 'Spec' },
          ]}
          onChange={(v) => setTweak('roster', v)} />
        <div style={{ font: '10px/1.4 ui-monospace, monospace', color: 'rgba(41,38,27,.5)',
          padding: '2px 2px 4px', letterSpacing: '0.04em' }}>
          {rosterPack.note}
        </div>

        <TweakSection label="Motion + state" />
        <TweakSlider label="Transition" value={t.motionMs}
          min={80} max={500} step={10} unit="ms"
          onChange={(v) => setTweak('motionMs', v)} />
        <TweakToggle label="Show contextual meta" value={t.showMeta}
          onChange={(v) => setTweak('showMeta', v)} />
        <TweakToggle label="Coach badge (1 new)" value={t.badge}
          onChange={(v) => setTweak('badge', v)} />
        <TweakToggle label="Dark mode" value={t.dark}
          onChange={(v) => setTweak('dark', v)} />

        <TweakSection label="Active tab" />
        <TweakSelect label="Selected"
          value={active}
          options={roster.map(r => ({ value: r.id, label: r.label }))}
          onChange={(v) => setTweak('active', v)} />
      </TweaksPanel>
    </div>
  );
};

// Rich TRENDS body — coral hero number, 6-week sparkline, zone-distribution bar.
// Lives separately so the rest of the prototype can stay tile-grid simple.
const TrendsRichBody = ({ dark }) => {
  const splitTrend = [58, 61, 60, 67, 69, 71]; // weekly negative-split %
  const zones = [
    { name: 'EASY',  pct: 64, color: 'var(--mood-energized)' },
    { name: 'TEMPO', pct: 22, color: 'var(--mood-tired)' },
    { name: 'THRSH', pct: 8,  color: 'var(--coral)' },
    { name: 'SPEED', pct: 6,  color: 'var(--mood-speed)' },
  ];
  const w = 320, h = 64;
  const min = Math.min(...splitTrend), max = Math.max(...splitTrend);
  const xs = splitTrend.map((_, i) => (i / (splitTrend.length - 1)) * w);
  const ys = splitTrend.map(v => h - ((v - min) / (max - min || 1)) * (h - 14) - 6);
  const path = xs.map((x, i) => `${i === 0 ? 'M' : 'L'} ${x} ${ys[i]}`).join(' ');
  const lastX = xs[xs.length - 1], lastY = ys[ys.length - 1];
  const muted = dark ? 'rgba(245,243,240,0.62)' : 'var(--ink-2)';
  return (
    <React.Fragment>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
        <div style={{
          fontFamily: 'var(--font-mono)', fontSize: 10, letterSpacing: '0.14em',
          color: muted, textTransform: 'uppercase',
        }}>TRENDS · 6 WEEKS</div>
        <div style={{
          fontFamily: 'var(--font-mono)', fontSize: 10, letterSpacing: '0.10em',
          color: 'var(--coral)', textTransform: 'uppercase',
        }}>↑ +12 PTS VS 6WK</div>
      </div>
      <div style={{
        fontFamily: 'var(--font-display)', fontWeight: 700, fontSize: 30,
        lineHeight: 1.02, color: 'var(--ink)', letterSpacing: '-0.01em', marginTop: -2,
      }}>Negative splits.</div>
      {/* hero number + sparkline */}
      <div style={{ display: 'flex', alignItems: 'flex-end', gap: 4, marginTop: 2 }}>
        <span style={{
          fontFamily: 'var(--font-mono)', fontWeight: 600, fontSize: 60, lineHeight: 0.85,
          color: 'var(--coral)', fontVariantNumeric: 'tabular-nums', letterSpacing: '-0.02em',
        }}>71</span>
        <span style={{
          fontFamily: 'var(--font-mono)', fontSize: 18, color: muted, lineHeight: 1,
          paddingBottom: 4, fontVariantNumeric: 'tabular-nums',
        }}>%</span>
        <span style={{ flex: 1 }} />
        <svg viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none"
          style={{ width: 168, height: 56 }}>
          <path d={path} fill="none" stroke={dark ? '#F5F3F0' : 'var(--ink)'}
            strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
          <circle cx={lastX} cy={lastY} r="3.5" fill="var(--coral)" />
        </svg>
      </div>
      <div style={{
        fontFamily: 'var(--font-body)', fontStyle: 'italic', fontSize: 13,
        color: muted, lineHeight: 1.5, marginTop: 2,
      }}>Back halves consistently faster than fronts — six weeks running.</div>

      {/* Zone bar */}
      <div style={{ marginTop: 6 }}>
        <div style={{
          fontFamily: 'var(--font-mono)', fontSize: 9, letterSpacing: '0.14em',
          color: muted, textTransform: 'uppercase', marginBottom: 8,
        }}>Pace zones · this week</div>
        <div style={{
          display: 'flex', height: 10, borderRadius: 3, overflow: 'hidden',
          boxShadow: dark ? 'none' : 'inset 0 0 0 0.5px rgba(0,0,0,0.04)',
        }}>
          {zones.map((z, i) => (
            <div key={i} style={{ background: z.color, width: z.pct + '%' }} />
          ))}
        </div>
        <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 10, gap: 6 }}>
          {zones.map((z, i) => (
            <div key={i} style={{
              display: 'flex', flexDirection: 'column', alignItems: 'flex-start',
              gap: 3, flex: 1, minWidth: 0,
            }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
                <div style={{ width: 6, height: 6, borderRadius: 999, background: z.color }} />
                <span style={{
                  fontFamily: 'var(--font-mono)', fontSize: 9, letterSpacing: '0.10em',
                  color: muted, textTransform: 'uppercase',
                }}>{z.name}</span>
              </div>
              <div style={{
                fontFamily: 'var(--font-mono)', fontWeight: 600, fontSize: 14,
                color: 'var(--ink)', fontVariantNumeric: 'tabular-nums',
              }}>{z.pct}<span style={{ fontSize: 9, color: muted, fontWeight: 500 }}>%</span></div>
            </div>
          ))}
        </div>
      </div>
    </React.Fragment>
  );
};

// Faux screen body that updates with tab selection — gives the prototype
// real-feeling content without pulling in the full app.
const PrototypeScreen = ({ tabId, dark }) => {
  if (tabId === 'trends') return <TrendsRichBody dark={dark} />;
  const screens = {
    log: {
      eyebrow: 'TODAY · LOG',
      title: 'May 21st.',
      sub: 'Easy 6 on the menu — keep heart rate sub-150.',
      stats: [
        { label: 'AVG PACE', value: '7:42', unit: '/mi' },
        { label: 'MILES',    value: '6.0' },
        { label: 'HR AVG',   value: '142', unit: 'bpm' },
      ],
    },
    train: {
      eyebrow: 'BLOCK · MARATHON · WK 12',
      title: 'Threshold workout.',
      sub: '4 × 1mi at half-marathon effort. Full recovery jog between.',
      stats: [
        { label: 'TOTAL', value: '8.2', unit: 'mi' },
        { label: 'TARGET', value: '6:48', unit: '/mi' },
        { label: 'EFFORT', value: 'HARD' },
      ],
    },
    trends: {
      eyebrow: 'TRENDS · 4 WEEKS',
      title: 'Negative split rate · 71%',
      sub: 'You\'re running the back halves faster than the fronts. Build that habit.',
      stats: [
        { label: 'VOLUME', value: '37', unit: 'mi/wk' },
        { label: 'PACE',   value: '7:52', unit: '/mi' },
        { label: 'TRIM',   value: '+12', unit: 'tss' },
      ],
    },
    coach: {
      eyebrow: 'FROM YOUR COACH',
      title: 'Tuesday\'s session.',
      sub: '"Sit at threshold longer — your last rep was 4 seconds slow on purpose. Don\'t over-cook the first one."',
      stats: [
        { label: 'REPLIES', value: '3' },
        { label: 'PINNED',  value: '2' },
        { label: 'STATUS',  value: 'AHEAD' },
      ],
    },
    plan: {
      eyebrow: 'PLAN · BOSTON \'27',
      title: 'Week 12 / 16.',
      sub: 'Peak week — 52 miles, two quality days. Cut-down begins next week.',
      stats: [
        { label: 'WEEK',  value: '52', unit: 'mi' },
        { label: 'LONG',  value: '22', unit: 'mi' },
        { label: 'QUAL',  value: '2', unit: 'days' },
      ],
    },
    runs: {
      eyebrow: 'RUNS · THIS WEEK',
      title: 'Four entries.',
      sub: 'Sun long · Mon easy · Tue threshold · Wed rest. Three logged · one to go.',
      stats: [
        { label: 'MILES', value: '28.4' },
        { label: 'TIME',  value: '3:42' },
        { label: 'AVG',   value: '7:51', unit: '/mi' },
      ],
    },
  };
  const s = screens[tabId] || screens.log;
  return (
    <React.Fragment>
      <div style={{
        fontFamily: 'var(--font-mono)', fontSize: 10, letterSpacing: '0.14em',
        color: 'var(--ink-2)', textTransform: 'uppercase',
      }}>{s.eyebrow}</div>
      <div style={{
        fontFamily: 'var(--font-display)', fontWeight: 700, fontSize: 36, lineHeight: 1.02,
        color: 'var(--ink)', letterSpacing: '-0.01em', marginTop: -2,
      }}>{s.title}</div>
      <div style={{
        fontFamily: 'var(--font-body)', fontStyle: 'italic', fontSize: 14,
        color: 'var(--ink-2)', lineHeight: 1.5, marginTop: -4,
      }}>{s.sub}</div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 8, marginTop: 6 }}>
        {s.stats.map((st, i) => (
          <div key={i} style={{
            background: 'var(--card)',
            borderRadius: 12, padding: '14px 12px',
            display: 'flex', flexDirection: 'column', gap: 8,
            boxShadow: dark ? 'none' : '0 2px 8px rgba(0,0,0,0.06)',
            border: dark ? '1px solid rgba(245,243,240,0.08)' : 'none',
          }}>
            <div style={{
              fontFamily: 'var(--font-mono)', fontSize: 9, letterSpacing: '0.10em',
              color: 'var(--ink-2)', textTransform: 'uppercase',
            }}>{st.label}</div>
            <div style={{
              fontFamily: 'var(--font-mono)', fontSize: 22, fontWeight: 600,
              color: 'var(--ink)', lineHeight: 1, display: 'flex',
              alignItems: 'baseline', gap: 3,
            }}>
              {st.value}
              {st.unit && <span style={{ fontSize: 9, color: 'var(--ink-2)' }}>{st.unit}</span>}
            </div>
          </div>
        ))}
      </div>
      {dark ? null : (
        <div style={{
          marginTop: 4, padding: '10px 0', borderTop: '1px solid var(--rule)',
          fontFamily: 'var(--font-mono)', fontSize: 9, letterSpacing: '0.14em',
          color: 'var(--ink-3)', textTransform: 'uppercase',
        }}>— continued —</div>
      )}
    </React.Fragment>
  );
};

// Override card background for dark-state cards to inherit dark vars
const cardDarkStyle = { ...darkModeVars, '--card': '#23211D' };

// ─── App · the design canvas ────────────────────────────────────────
const App = () => (
  <DesignCanvas
    title="Tab Bar Lab"
    subtitle="Post Run Drip · iOS · 6 explorations → naming → states → live prototype"
  >
    {/* ── 1. The 6 explorations ──────────────────────────────────── */}
    <DCSection id="explorations" title="01 · Six explorations"
      subtitle="Tap any bar to feel how the active state moves. All six render on warm paper at 390pt — what an iPhone actually sees.">
      {Object.values(TAB_VARIANTS).map(v => (
        <DCArtboard key={v.id} id={'var-' + v.id} label={v.label}
          width={390} height={240}>
          <VariantCard variantId={v.id}
            roster={v.id === 'serif' ? window.ROSTER_SERIF_CURRENT : window.ROSTER_SHORT} />
        </DCArtboard>
      ))}
    </DCSection>

    {/* ── 2. Naming roster comparison ───────────────────────────── */}
    <DCSection id="rosters" title="02 · Naming rosters"
      subtitle="Three candidates, rendered on the canonical bar. TRAINING fits — barely. TRAIN breathes. RUNS reads as a fifth surface, not a synonym for LOG.">
      <DCArtboard id="r-current" label="A · Current — LOG · TRAINING · TRENDS · COACH · PLAN"
        width={390} height={108}>
        <RosterCard roster={window.ROSTER_CURRENT} />
      </DCArtboard>
      <DCArtboard id="r-short" label="B · Shortened — LOG · TRAIN · TRENDS · COACH · PLAN"
        width={390} height={108}>
        <RosterCard roster={window.ROSTER_SHORT} />
      </DCArtboard>
      <DCArtboard id="r-spec" label="C · Spec — LOG · TRAIN · TRENDS · COACH · RUNS"
        width={390} height={108}>
        <RosterCard roster={window.ROSTER_SPEC} />
      </DCArtboard>
    </DCSection>

    {/* ── 3. States ─────────────────────────────────────────────── */}
    <DCSection id="states" title="03 · States"
      subtitle="The chosen direction — canonical — across every state SwiftUI needs to land. Pressed = dot shrinks 0.65× over 80ms, label dims to ink-3. Badge sits to the right of the active label so it doesn't crowd the dot column.">
      <DCArtboard id="s-default" label="Default · LOG active" width={390} height={140}>
        <StateCard title="DEFAULT" note="LOG ACTIVE">
          <TabBarV1Canonical active="log" onChange={() => {}} roster={window.ROSTER_SHORT} />
        </StateCard>
      </DCArtboard>
      <DCArtboard id="s-pressed" label="Pressed · finger on LOG" width={390} height={140}>
        <StateCard title="PRESSED" note="MID-TAP ON LOG">
          <PressedCanonical active="train" pressed="log" roster={window.ROSTER_SHORT} />
        </StateCard>
      </DCArtboard>
      <DCArtboard id="s-badge" label="Badge · Coach has 1 new" width={390} height={140}>
        <StateCard title="BADGE" note="UNREAD ON COACH">
          <BadgeCanonical active="log" badgeOn="coach" roster={window.ROSTER_SHORT} />
        </StateCard>
      </DCArtboard>
      <DCArtboard id="s-disabled" label="Disabled · no plan yet" width={390} height={140}>
        <StateCard title="DISABLED" note="PLAN — NO PLAN YET">
          <DisabledCanonical active="log" disabled={['plan']} roster={window.ROSTER_SHORT} />
        </StateCard>
      </DCArtboard>
      <DCArtboard id="s-dark" label="Dark · inactive" width={390} height={140}>
        <div style={cardDarkStyle}>
          <StateCard title="DARK · LOG ACTIVE" note="WARM-BLACK PAPER" dark>
            <TabBarV1Canonical active="log" onChange={() => {}} roster={window.ROSTER_SHORT} />
          </StateCard>
        </div>
      </DCArtboard>
      <DCArtboard id="s-dark-badge" label="Dark · Coach badge + Train active" width={390} height={140}>
        <div style={cardDarkStyle}>
          <StateCard title="DARK · WITH BADGE" note="TRAIN ACTIVE · COACH NEW" dark>
            <BadgeCanonical active="train" badgeOn="coach" roster={window.ROSTER_SHORT} />
          </StateCard>
        </div>
      </DCArtboard>
    </DCSection>

    {/* ── 4. Prototype ──────────────────────────────────────────── */}
    <DCSection id="prototype" title="04 · Live prototype"
      subtitle="Full 390 × 844 iPhone. Toggle the Tweaks panel (top-right of the workspace) to swap variant, roster, motion timing, badge, dark mode. Active tab swaps the screen body too — so each variant gets stress-tested against real content lengths.">
      <DCArtboard id="proto" label="iPhone · 390 × 844 · all six variants live"
        width={430} height={874}>
        <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'flex-start',
          paddingTop: 12, height: '100%' }}>
          <PrototypeFrame />
        </div>
      </DCArtboard>
    </DCSection>
  </DesignCanvas>
);

// Small helper for rosters section
const RosterCard = ({ roster }) => (
  <div style={{
    width: 390, height: '100%', background: 'var(--paper)',
    display: 'flex', flexDirection: 'column', justifyContent: 'flex-end',
  }}>
    <TabBarV1Canonical active="log" onChange={() => {}} roster={roster} />
    <div style={{
      height: 22, display: 'flex', alignItems: 'center', justifyContent: 'center',
      background: 'var(--paper)',
    }}>
      <div style={{ width: 130, height: 4, borderRadius: 999, background: 'rgba(0,0,0,0.18)' }} />
    </div>
  </div>
);

// Mount
const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<App />);

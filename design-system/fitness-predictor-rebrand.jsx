/* global React, Eyebrow, EditorialRule, Hairline, PlateStrip, Section, TabBar, MoodPill */
/* ════════════════════════════════════════════════════════════════════
   FITNESS PREDICTOR · BRAND REBRAND
   Same screen as the production iOS view, brought in line with PRD:
   • Plate strip + editorial rules (no chunky nav bar)
   • Crimson Pro display + mono tabular numerals (no system sans)
   • One coral per visual cluster (the active hit, never the room)
   • Hairlines between cells, no card-in-card
   • Network error is quiet italic, never a coral fill
   ════════════════════════════════════════════════════════════════════ */

const { useState } = React;

/* ── helpers ─────────────────────────────────────────────────────── */

const fpStyles = {
  meta: {
    fontFamily: "var(--font-mono)",
    fontSize: 10,
    fontWeight: 500,
    letterSpacing: "0.12em",
    color: "var(--ink-2)",
    textTransform: "uppercase",
  },
  metaSm: {
    fontFamily: "var(--font-mono)",
    fontSize: 9,
    fontWeight: 500,
    letterSpacing: "0.10em",
    color: "var(--ink-3)",
    textTransform: "uppercase",
  },
  display: {
    fontFamily: "var(--font-mono)",
    fontWeight: 600,
    fontVariantNumeric: "tabular-nums",
    color: "var(--ink)",
    lineHeight: 1,
  },
  italic: {
    fontFamily: "var(--font-body)",
    fontStyle: "italic",
    color: "var(--ink-2)",
  },
};

/* ── error banner — brand-aligned (quiet, italic, secondary) ─────── */

const OfflineNotice = () => (
  <div style={{
    margin: "10px 24px 0 24px",
    padding: "10px 0",
    borderTop: "1px solid var(--rule)",
    borderBottom: "1px solid var(--rule)",
    display: "flex",
    gap: 14,
    alignItems: "baseline",
  }}>
    <span style={{ ...fpStyles.meta, color: "var(--coral)" }}>Network · Offline</span>
    <p style={{
      ...fpStyles.italic, fontSize: 13, lineHeight: 1.4, margin: 0, flex: 1,
    }}>
      Couldn't refresh — showing the last cached prediction from 4 hours ago.
    </p>
  </div>
);

/* ── anchor row ──────────────────────────────────────────────────── */

const AnchorStrip = ({ a }) => (
  <div style={{ display: "flex", flexDirection: "column", gap: 4, marginTop: 4 }}>
    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
      <span style={fpStyles.meta}>Anchored on</span>
      <span style={fpStyles.metaSm}>{a.weeks}w ago</span>
    </div>
    <div style={{ display: "flex", alignItems: "baseline", gap: 10 }}>
      <span style={{ ...fpStyles.meta, color: "var(--coral)" }}>{a.race}</span>
      <span style={{ ...fpStyles.display, fontSize: 26 }}>{a.time}</span>
    </div>
    <p style={{ ...fpStyles.italic, fontSize: 13, margin: 0, lineHeight: 1.45 }}>
      {a.subtitle}
    </p>
  </div>
);

/* ── one predicted-time row ──────────────────────────────────────── */

/* Each row gets all three splits — 400m, 1K, mile — in tabular mono.
   The distance's "marquee" split (the one a runner actually plans by)
   is the coral hit; the other two are ink-2. */
const SplitTriple = ({ splits, marquee }) => (
  <div style={{
    display: "grid",
    gridTemplateColumns: "repeat(3, 1fr)",
    gap: 0,
    marginTop: 10,
    borderTop: "1px solid var(--rule)",
  }}>
    {[
      { id: "p400", label: "400 m" },
      { id: "p1k",  label: "per km" },
      { id: "pmi",  label: "per mi" },
    ].map((s, i) => {
      const isMarquee = s.id === marquee;
      return (
        <div key={s.id} style={{
          display: "flex", flexDirection: "column", gap: 4,
          padding: "10px 12px 6px 0",
          borderRight: i < 2 ? "1px solid var(--rule)" : 0,
          paddingLeft: i === 0 ? 0 : 12,
        }}>
          <span style={{
            ...fpStyles.metaSm,
            color: isMarquee ? "var(--coral)" : "var(--ink-3)",
          }}>{s.label}</span>
          <span style={{
            fontFamily: "var(--font-mono)",
            fontSize: 14, fontWeight: 600,
            letterSpacing: "0.02em",
            fontVariantNumeric: "tabular-nums",
            color: isMarquee ? "var(--coral)" : "var(--ink)",
          }}>{splits[s.id]}</span>
        </div>
      );
    })}
  </div>
);

const RaceRow = ({ r, isLast }) => (
  <div style={{
    padding: "14px 0",
    borderBottom: isLast ? "0" : "1px solid var(--rule)",
  }}>
    {/* head row — label + display time + range */}
    <div style={{
      display: "grid",
      gridTemplateColumns: "1fr auto",
      gap: 6,
      alignItems: "baseline",
    }}>
      <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
        <span style={fpStyles.meta}>{r.label}</span>
        <span style={{ ...fpStyles.display, fontSize: r.bigFinish ? 30 : 28 }}>{r.time}</span>
      </div>
      <span style={{
        ...fpStyles.metaSm, fontVariantNumeric: "tabular-nums",
        alignSelf: "flex-end",
      }}>{r.range}</span>
    </div>

    {/* splits — 400 · 1K · mile, one coral marquee */}
    <SplitTriple splits={r.splits} marquee={r.marquee} />
  </div>
);

/* ── PACES tab — colored marker + label + mono pace ──────────────── */

const PACE_COLORS = {
  easy:      "var(--mood-energized)",
  long:      "var(--mood-positive)",
  marathon:  "var(--coral-light)",
  threshold: "var(--coral)",
  interval:  "var(--mood-tired)",
};

const PaceRow = ({ id, label, splits, marquee }) => (
  <div style={{
    display: "grid",
    gridTemplateColumns: "auto auto 1fr",
    alignItems: "center",
    gap: 12,
    padding: "12px 0",
    borderBottom: "1px solid var(--rule)",
  }}>
    <div style={{
      width: 3, height: 18, borderRadius: 1,
      background: PACE_COLORS[id],
    }} />
    <span style={{
      fontFamily: "var(--font-body)", fontSize: 14, color: "var(--ink)",
    }}>{label}</span>
    <div style={{
      display: "flex", gap: 8, justifyContent: "flex-end",
      alignItems: "baseline",
      fontFamily: "var(--font-mono)", fontSize: 12, fontWeight: 600,
      fontVariantNumeric: "tabular-nums", letterSpacing: "0.02em",
    }}>
      {[
        { id: "p400", suffix: " / 400" },
        { id: "p1k",  suffix: " / km"  },
        { id: "pmi",  suffix: " / mi"  },
      ].map((s, i) => {
        const isMarquee = s.id === marquee;
        return (
          <React.Fragment key={s.id}>
            {i > 0 && <span style={{ color: "var(--ink-3)" }}>·</span>}
            <span style={{ color: isMarquee ? "var(--coral)" : "var(--ink)" }}>
              {splits[s.id]}<span style={{ color: isMarquee ? "var(--coral)" : "var(--ink-2)", fontWeight: 500 }}>{s.suffix}</span>
            </span>
          </React.Fragment>
        );
      })}
    </div>
  </div>
);

/* ── STIMULUS tab — 4 stats grid ─────────────────────────────────── */

const Stim = ({ value, unit, label, trend }) => (
  <div style={{ display: "flex", flexDirection: "column", gap: 4, padding: "4px 0" }}>
    <div style={{ display: "flex", alignItems: "baseline", gap: 4 }}>
      <span style={{ ...fpStyles.display, fontSize: 22 }}>{value}</span>
      {unit && (
        <span style={{
          fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-2)",
          fontWeight: 600,
        }}>{unit}</span>
      )}
      {trend && (
        <span style={{
          fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 600,
          color: trend === "up" ? "var(--mood-energized)" : trend === "down" ? "var(--coral)" : "var(--ink-3)",
        }}>{trend === "up" ? "↑" : trend === "down" ? "↓" : "→"}</span>
      )}
    </div>
    <span style={fpStyles.metaSm}>{label}</span>
  </div>
);

/* ── segmented chips (Week/Month/Custom, Zones/%MP) ──────────────── */

const Segmented = ({ items, value, onChange, size = "sm" }) => (
  <div style={{ display: "flex", gap: 4, alignItems: "center" }}>
    {items.map(it => {
      const active = it.id === value;
      return (
        <button key={it.id}
          onClick={() => onChange && onChange(it.id)}
          style={{
            background: active ? "var(--coral-wash)" : "transparent",
            border: 0,
            padding: size === "sm" ? "3px 8px" : "4px 10px",
            borderRadius: 999,
            cursor: "pointer",
            fontFamily: "var(--font-mono)",
            fontSize: size === "sm" ? 10 : 11,
            fontWeight: 600,
            letterSpacing: "0.10em",
            color: active ? "var(--coral)" : "var(--ink-2)",
            textTransform: "uppercase",
          }}>{it.label}</button>
      );
    })}
  </div>
);

/* ════════════════════════════════════════════════════════════════════
   MAIN SCREEN
   ════════════════════════════════════════════════════════════════════ */

const FitnessPredictorRebrand = ({ offline = false, empty = false }) => {
  const [tab, setTab] = useState("paces");
  const [period, setPeriod] = useState("week");
  const [volTab, setVolTab] = useState("zones");

  const anchor = {
    race: "10K",
    time: "31:24",
    weeks: 14,
    subtitle: "Feb 7, 2026 — your most recent timed effort. The forward read is rooted here.",
  };

  const races = [
    { label: "Mile",     time: "4:30",  range: "4:26 – 4:34",
      marquee: "p400",
      splits: { p400: "1:07", p1k: "2:48", pmi: "4:30" } },
    { label: "5K",       time: "15:32", range: "15:19 – 15:45",
      marquee: "p1k",
      splits: { p400: "1:15", p1k: "3:06", pmi: "5:00" } },
    { label: "10K",      time: "32:18", range: "31:49 – 32:47",
      marquee: "p1k",
      splits: { p400: "1:18", p1k: "3:14", pmi: "5:12" } },
    { label: "Half",     time: "1:11",  range: "1:10 – 1:12",
      marquee: "pmi",
      splits: { p400: "1:21", p1k: "3:23", pmi: "5:26" } },
    { label: "Marathon", time: "2:29",  range: "2:27 – 2:31",
      marquee: "pmi",
      splits: { p400: "1:25", p1k: "3:32", pmi: "5:41" }, bigFinish: true },
  ];

  const paces = [
    { id: "easy",      label: "Easy",      marquee: "pmi",
      splits: { p400: "1:47", p1k: "4:27", pmi: "7:10" } },
    { id: "long",      label: "Long Run",  marquee: "pmi",
      splits: { p400: "1:53", p1k: "4:44", pmi: "7:37" } },
    { id: "marathon",  label: "Marathon",  marquee: "pmi",
      splits: { p400: "1:25", p1k: "3:32", pmi: "5:41" } },
    { id: "threshold", label: "Threshold", marquee: "pmi",
      splits: { p400: "1:20", p1k: "3:21", pmi: "5:24" } },
    { id: "interval",  label: "Interval",  marquee: "p400",
      splits: { p400: "1:15", p1k: "3:06", pmi: "5:00" } },
  ];

  return (
    <div className="page">
      <PlateStrip
        surface="FITNESS PREDICTOR · FORWARD READ"
        fig="FIG. 29"
        right="TRENDS · 05.2026"
      />

      {offline && <OfflineNotice />}

      <div className="page__body">

        {/* ── top chrome row ─────────────────────────────────── */}
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
          <a className="link" style={{ fontSize: 13 }}>Back</a>
          <a className="link" style={{ fontSize: 13, fontStyle: "italic", borderBottom: "0" }}>
            Refresh ↻
          </a>
        </div>

        {/* ── dateline ──────────────────────────────────────── */}
        <div className="section section--first" style={{ marginTop: 12 }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
            <Eyebrow coral>Today · May 22</Eyebrow>
            <Eyebrow>Reading ⟶ Trends</Eyebrow>
          </div>
          <h1 className="h-display" style={{ fontSize: 32, marginTop: 2 }}>
            Predicted times.
          </h1>
          <p style={{
            ...fpStyles.italic, fontSize: 14, lineHeight: 1.5,
            margin: "6px 0 0 0",
          }}>
            Off today's fitness — what the next five distances look like, give or take a few seconds.
          </p>
        </div>

        <div style={{ height: 18 }} />
        <EditorialRule />
        <div style={{ height: 14 }} />

        {/* ── anchor ───────────────────────────────────────── */}
        <AnchorStrip a={anchor} />

        <div style={{ height: 18 }} />
        <EditorialRule />

        {/* ── 5 predicted times — flat editorial list ───────── */}
        <div style={{ marginTop: 6 }}>
          {races.map((r, i) => (
            <RaceRow key={r.label} r={r} isLast={i === races.length - 1} />
          ))}
        </div>

        <p style={{
          ...fpStyles.italic, fontSize: 11, lineHeight: 1.45,
          color: "var(--ink-3)", margin: "10px 0 0 0",
        }}>
          Range is where the time lives 80% of the time, off today's fitness. Marathon and half round to the minute — seconds at that distance are math, not signal.
        </p>

        <div style={{ height: 24 }} />
        <EditorialRule />

        {/* ── training paces / stimulus ──────────────────────── */}
        <Section
          eyebrow={
            <span style={{ display: "flex", gap: 12, alignItems: "baseline" }}>
              <span style={{
                cursor: "pointer",
                color: tab === "paces" ? "var(--ink)" : "var(--ink-3)",
                fontWeight: tab === "paces" ? 600 : 500,
              }} onClick={() => setTab("paces")}>Paces</span>
              <span style={{
                cursor: "pointer",
                color: tab === "stimulus" ? "var(--ink)" : "var(--ink-3)",
                fontWeight: tab === "stimulus" ? 600 : 500,
              }} onClick={() => setTab("stimulus")}>Stimulus</span>
            </span>
          }
          eyebrowRight={
            <span style={{
              fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 600,
              letterSpacing: "0.10em", color: "var(--coral)", textTransform: "uppercase",
              padding: "3px 8px", borderRadius: 999, background: "var(--coral-wash)",
            }}>Maintaining</span>
          }
        >
          {tab === "paces" ? (
            <div style={{ marginTop: 8 }}>
              {paces.map(p => <PaceRow key={p.id} {...p} />)}
            </div>
          ) : (
            <div style={{
              display: "grid", gridTemplateColumns: "repeat(4, 1fr)",
              gap: 0, marginTop: 12,
              borderTop: "1px solid var(--rule)",
              borderBottom: "1px solid var(--rule)",
              padding: "10px 0",
            }}>
              <Stim value="38" unit="mi" label="per week" trend="up" />
              <Stim value="5"  unit="ct" label="runs / wk" />
              <Stim value="62" unit="min" label="hard min" trend="up" />
              <Stim value="2"  unit="ct" label="quality" />
            </div>
          )}
        </Section>

        <div style={{ height: 24 }} />
        <EditorialRule />

        {/* ── training volume ────────────────────────────────── */}
        <Section
          eyebrow="Training volume"
          eyebrowRight={
            <Segmented
              value={period} onChange={setPeriod}
              items={[
                { id: "week",   label: "Week"   },
                { id: "month",  label: "Month"  },
                { id: "custom", label: "Custom" },
              ]}
            />
          }
        >
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginTop: 10 }}>
            <Segmented
              value={volTab} onChange={setVolTab}
              items={[
                { id: "zones", label: "Zones" },
                { id: "mp",    label: "% MP" },
              ]}
            />
            <span style={{
              fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--ink-2)",
              fontVariantNumeric: "tabular-nums",
            }}>
              May 18 – May 22
              <span style={{ color: "var(--ink-3)" }}>{" · "}</span>
              <span style={{ color: "var(--ink)" }}>0.0 mi</span>
            </span>
          </div>

          {empty ? (
            <div style={{
              marginTop: 18, marginBottom: 4,
              padding: "20px 0",
              borderTop: "1px solid var(--rule)",
              borderBottom: "1px solid var(--rule)",
            }}>
              <p style={{
                ...fpStyles.italic, fontSize: 14, color: "var(--ink-2)",
                margin: 0, textAlign: "center", lineHeight: 1.5,
              }}>
                No data for this period. When you log a run, your minutes by zone land here.
              </p>
            </div>
          ) : (
            <div style={{ marginTop: 18 }}>
              {/* tiny placeholder bar chart — five bars */}
              <div style={{
                display: "grid", gridTemplateColumns: "repeat(5, 1fr)",
                gap: 8, alignItems: "end", height: 96,
                borderBottom: "1px solid var(--rule)", paddingBottom: 6,
              }}>
                {[42, 18, 28, 64, 12].map((h, i) => (
                  <div key={i} style={{
                    display: "flex", flexDirection: "column-reverse", gap: 2, height: "100%",
                  }}>
                    <div style={{ height: `${h * 0.6}%`, background: "var(--mood-energized)", opacity: 0.85 }} />
                    <div style={{ height: `${h * 0.25}%`, background: "var(--coral)", opacity: 0.75 }} />
                    <div style={{ height: `${h * 0.1}%`,  background: "var(--mood-tired)", opacity: 0.8 }} />
                  </div>
                ))}
              </div>
              <div style={{
                display: "grid", gridTemplateColumns: "repeat(5, 1fr)",
                gap: 8, marginTop: 6,
              }}>
                {["Mon", "Tue", "Wed", "Thu", "Fri"].map(d => (
                  <span key={d} style={{ ...fpStyles.metaSm, textAlign: "center" }}>{d}</span>
                ))}
              </div>
            </div>
          )}
        </Section>

        <div style={{ height: 32 }} />
      </div>
    </div>
  );
};

window.FitnessPredictorRebrand = FitnessPredictorRebrand;

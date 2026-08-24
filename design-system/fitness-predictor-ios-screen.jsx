/* global React, Eyebrow, Hairline, Section, PlateStrip, EditorialRule, TabBar, fmt, fmtDelta, sec, STATE */
/* ════════════════════════════════════════════════════════════════════
   FITNESS PREDICTOR SCREEN · iOS
   Renders the four scenarios via the `data` prop.
   ════════════════════════════════════════════════════════════════════ */

const { useState } = React;

/* ── shared bits ─────────────────────────────────────────────────── */

const StateBadge = ({ state }) => {
  const s = STATE[state] || STATE.moderate;
  return (
    <span style={{
      fontFamily: "var(--font-mono)", fontSize: 9, fontWeight: 600,
      letterSpacing: "0.14em", color: s.color, textTransform: "uppercase",
    }}>{s.lbl}</span>
  );
};

/* horizontal range band w/ prediction tick + PR diamond */
const Band = ({ low, pred, high, pr, state }) => {
  const half = Math.max(pred - low, high - pred, Math.abs(pr - pred), 1) * 1.25;
  const toPct = (t) => 50 + ((t - pred) / half) * 46;
  const lowPct = toPct(low), highPct = toPct(high), prPct = toPct(pr);
  const accent = state === "tight" ? "var(--mood-energized)"
              : state === "wide"  ? "var(--coral)"
              :                     "var(--ink)";
  const bandOpacity = state === "tight" ? 0.22 : state === "wide" ? 0.18 : 0.14;
  return (
    <div style={{ position: "relative", height: 26, marginTop: 8 }}>
      {/* center axis */}
      <div style={{ position: "absolute", top: "50%", left: 0, right: 0, height: 1, background: "var(--rule)" }} />
      {/* band */}
      <div style={{
        position: "absolute", top: "50%", transform: "translateY(-50%)",
        left: `${lowPct}%`, width: `${Math.max(0.5, highPct - lowPct)}%`,
        height: 8, background: accent, opacity: bandOpacity, borderRadius: 1,
      }} />
      {/* low/high caps */}
      <div style={{ position: "absolute", top: "50%", transform: "translateY(-50%)", left: `${lowPct}%`, width: 1, height: 12, background: "var(--ink-3)" }} />
      <div style={{ position: "absolute", top: "50%", transform: "translateY(-50%)", left: `${highPct}%`, width: 1, height: 12, background: "var(--ink-3)" }} />
      {/* PR diamond */}
      <div style={{
        position: "absolute", top: "50%", left: `${prPct}%`,
        width: 7, height: 7, background: "var(--paper)",
        border: `1.2px solid var(--ink-2)`,
        transform: "translate(-50%, -50%) rotate(45deg)",
      }} />
      {/* prediction tick */}
      <div style={{
        position: "absolute", top: "50%", left: "50%",
        width: 2, height: 18, background: accent,
        transform: "translate(-50%, -50%)", borderRadius: 1,
      }} />
    </div>
  );
};

/* ── PREDICTION ROW (collapsible) ─────────────────────────────────── */

const PredictionRow = ({ p, expanded, onToggle }) => {
  const deltaPr = p.pred - p.pr;
  const isGoal = p.goal;
  return (
    <div
      onClick={onToggle}
      style={{
        padding: "14px 0",
        borderBottom: "1px solid var(--rule)",
        cursor: "pointer",
        background: isGoal ? "rgba(212,89,42,0.025)" : "transparent",
        marginLeft: isGoal ? -8 : 0, marginRight: isGoal ? -8 : 0,
        paddingLeft: isGoal ? 8 : 0, paddingRight: isGoal ? 8 : 0,
      }}
    >
      {/* head row */}
      <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between" }}>
        <div style={{ display: "flex", alignItems: "baseline", gap: 8 }}>
          <span style={{
            fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 600,
            letterSpacing: "0.14em", color: "var(--ink-2)",
          }}>{p.label}</span>
          {isGoal && (
            <span style={{
              fontFamily: "var(--font-mono)", fontSize: 9, fontWeight: 600,
              letterSpacing: "0.14em", color: "var(--coral)",
            }}>· GOAL RACE</span>
          )}
        </div>
        <StateBadge state={p.state} />
      </div>

      {/* time row */}
      <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between", marginTop: 6 }}>
        <span style={{
          fontFamily: "var(--font-mono)", fontWeight: 600, fontSize: 26,
          color: "var(--ink)", fontVariantNumeric: "tabular-nums", lineHeight: 1,
        }}>{fmt(p.pred)}</span>
        <span style={{
          fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--ink-2)",
          fontVariantNumeric: "tabular-nums",
        }}>
          ±{fmt((p.high - p.low) / 2)}
        </span>
      </div>

      {/* band */}
      <Band low={p.low} pred={p.pred} high={p.high} pr={p.pr} state={p.state} />

      {/* low / high labels */}
      <div style={{ display: "flex", justifyContent: "space-between", marginTop: 4 }}>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)", letterSpacing: "0.10em", fontVariantNumeric: "tabular-nums" }}>{fmt(p.low)}</span>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)", letterSpacing: "0.10em", textTransform: "uppercase" }}>
          ◆ PR {fmt(p.pr)} · {p.prDate}
        </span>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)", letterSpacing: "0.10em", fontVariantNumeric: "tabular-nums" }}>{fmt(p.high)}</span>
      </div>

      {/* reasoning + chevron */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginTop: 8 }}>
        <p style={{
          fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13,
          color: "var(--ink-2)", margin: 0, lineHeight: 1.45, flex: 1,
        }}>{p.reasoning}</p>
        <span style={{
          fontFamily: "var(--font-mono)", fontSize: 12, color: "var(--ink-3)",
          marginLeft: 12, transform: expanded ? "rotate(90deg)" : "none",
          transition: "transform .2s",
        }}>›</span>
      </div>

      {/* expanded: sharpen + vs PR */}
      {expanded && (
        <div style={{ marginTop: 10, paddingTop: 10, borderTop: "1px dashed var(--rule)", display: "flex", flexDirection: "column", gap: 6 }}>
          <div style={{ display: "flex", justifyContent: "space-between" }}>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-2)", letterSpacing: "0.10em", textTransform: "uppercase" }}>vs PR</span>
            <span style={{
              fontFamily: "var(--font-mono)", fontSize: 12, fontWeight: 600, fontVariantNumeric: "tabular-nums",
              color: deltaPr < 0 ? "var(--mood-energized)" : deltaPr > 0 ? "var(--coral)" : "var(--ink-2)",
            }}>{fmtDelta(deltaPr)}</span>
          </div>
          {p.sharpen && (
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 10 }}>
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--coral)", letterSpacing: "0.10em", textTransform: "uppercase" }}>SHARPEN</span>
              <span style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13, color: "var(--ink)", textAlign: "right" }}>
                {p.sharpen}
              </span>
            </div>
          )}
        </div>
      )}
    </div>
  );
};

/* ── ANCHOR CARD ─────────────────────────────────────────────────── */

const AnchorCard = ({ a }) => (
  <div style={{
    background: "var(--card)", borderRadius: 12, padding: "14px 16px",
    boxShadow: "0 2px 8px rgba(0,0,0,0.06)",
    display: "flex", flexDirection: "column", gap: 6, marginTop: 8,
  }}>
    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
      <span style={{
        fontFamily: "var(--font-mono)", fontSize: 9, fontWeight: 600,
        letterSpacing: "0.14em", color: "var(--coral)", textTransform: "uppercase",
      }}>ANCHORED ON</span>
      <span style={{
        fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)",
        letterSpacing: "0.10em", textTransform: "uppercase",
      }}>{a.when}</span>
    </div>
    <div style={{ display: "flex", alignItems: "baseline", gap: 10 }}>
      <span style={{ fontFamily: "var(--font-mono)", fontSize: 12, color: "var(--ink-2)" }}>{a.label}</span>
      <span style={{
        fontFamily: "var(--font-mono)", fontWeight: 600, fontSize: 30,
        color: "var(--ink)", fontVariantNumeric: "tabular-nums", lineHeight: 1,
      }}>{a.time}</span>
    </div>
    <p style={{
      fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13,
      color: "var(--ink-2)", margin: 0, lineHeight: 1.45,
    }}>{a.sub}</p>
  </div>
);

/* ── TRAJECTORY SPARK ────────────────────────────────────────────── */

const Trajectory = ({ t }) => {
  if (!t || !t.points) return null;
  const W = 320, H = 110, padL = 4, padR = 4, padT = 18, padB = 24;
  const innerW = W - padL - padR, innerH = H - padT - padB;
  const ys = t.points.map(p => p.pred);
  const min = Math.min(...ys, t.goalSec) - 60;
  const max = Math.max(...ys, t.goalSec) + 60;
  const xStep = innerW / Math.max(1, t.points.length - 1);
  const yFor = (v) => padT + ((max - v) / (max - min)) * innerH;
  const xFor = (i) => padL + i * xStep;

  const pts = t.points.map((p, i) => [xFor(i), yFor(p.pred)]);
  const linePath = pts.map(([x, y], i) => `${i === 0 ? "M" : "L"} ${x.toFixed(1)} ${y.toFixed(1)}`).join(" ");
  const goalY = yFor(t.goalSec);
  const currentIdx = t.points.findIndex(p => p.current);

  return (
    <svg viewBox={`0 0 ${W} ${H}`} style={{ width: "100%", height: H, display: "block" }}>
      {/* goal line */}
      <line x1={padL} x2={W - padR} y1={goalY} y2={goalY} stroke="var(--coral)" strokeWidth="1" strokeDasharray="3 3" opacity="0.7" />
      <text x={W - padR} y={goalY - 4} textAnchor="end" fontFamily="var(--font-mono)" fontSize="8.5" letterSpacing="1.1" fill="var(--coral)" fontWeight="600">GOAL 3:15</text>

      {/* prediction line */}
      <polyline points={pts.map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`).join(" ")}
        fill="none" stroke="var(--ink)" strokeWidth="1.5" strokeLinejoin="round" />

      {/* dots */}
      {pts.map(([x, y], i) => (
        <circle key={i} cx={x} cy={y} r={i === currentIdx ? 4 : 2} fill={i === currentIdx ? "var(--coral)" : "var(--ink)"} />
      ))}

      {/* current label */}
      {currentIdx >= 0 && (
        <text x={pts[currentIdx][0]} y={pts[currentIdx][1] - 9}
          textAnchor="end" fontFamily="var(--font-mono)" fontSize="10" fontWeight="700"
          fill="var(--coral)" style={{ fontVariantNumeric: "tabular-nums" }}>
          {fmt(t.points[currentIdx].pred)}
        </text>
      )}

      {/* x labels: first, middle, current */}
      {[0, Math.floor(t.points.length / 2), t.points.length - 1].map(i => (
        <text key={i} x={xFor(i)} y={H - 8}
          textAnchor={i === 0 ? "start" : i === t.points.length - 1 ? "end" : "middle"}
          fontFamily="var(--font-mono)" fontSize="8.5" letterSpacing="1" fill="var(--ink-3)">
          {t.points[i].label}
        </text>
      ))}
    </svg>
  );
};

/* ── GOAL vs CURRENT ─────────────────────────────────────────────── */

const GoalVsCurrent = ({ g }) => {
  const ahead = g.deltaSec < 0;
  const tone = g.flag ? "var(--coral)" : ahead ? "var(--mood-energized)" : "var(--ink-2)";
  return (
    <div style={{ paddingTop: 4 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
        <span style={{
          fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--ink)",
          fontWeight: 600, fontVariantNumeric: "tabular-nums",
        }}>{g.target}</span>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-3)", letterSpacing: "0.10em" }}>GOAL</span>
      </div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginTop: 8 }}>
        <span style={{
          fontFamily: "var(--font-mono)", fontWeight: 600, fontSize: 26,
          color: tone, fontVariantNumeric: "tabular-nums", lineHeight: 1,
        }}>{g.current}</span>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: tone, letterSpacing: "0.10em", fontWeight: 600 }}>
          {ahead ? "↓ " : g.deltaSec > 0 ? "↑ " : ""}{g.deltaSec === 0 ? "ON" : fmt(Math.abs(g.deltaSec))}
        </span>
      </div>
      <p style={{
        fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13,
        color: "var(--ink-2)", margin: "8px 0 0 0", lineHeight: 1.45,
      }}>{g.interp}</p>
    </div>
  );
};

/* ── SOFT-SPOT LIST ──────────────────────────────────────────────── */

const SoftSpot = ({ items }) => (
  <div style={{ display: "flex", flexDirection: "column", marginTop: 8 }}>
    {items.map((it, i) => (
      <div key={i} style={{
        display: "grid", gridTemplateColumns: "1fr auto",
        gap: 12, padding: "10px 0",
        borderBottom: i < items.length - 1 ? "1px solid var(--rule)" : "0",
      }}>
        <span style={{
          fontFamily: "var(--font-body)", fontSize: 14, color: "var(--ink)", lineHeight: 1.4,
        }}>{it.text}</span>
        <span style={{
          fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--coral)",
          letterSpacing: "0.12em", textTransform: "uppercase", whiteSpace: "nowrap",
          alignSelf: "center",
        }}>{it.impact}</span>
      </div>
    ))}
  </div>
);

/* ── CONTEXT LOG ─────────────────────────────────────────────────── */

const ContextLog = ({ items }) => (
  <div style={{ display: "flex", flexDirection: "column", marginTop: 8 }}>
    {items.map((it, i) => (
      <div key={i} style={{
        display: "grid", gridTemplateColumns: "54px 1fr",
        gap: 10, padding: "10px 0", alignItems: "baseline",
        borderBottom: i < items.length - 1 ? "1px solid var(--rule)" : "0",
      }}>
        <span style={{
          fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)",
          letterSpacing: "0.10em", textTransform: "uppercase",
        }}>{it.date}</span>
        <div>
          <div style={{ fontFamily: "var(--font-body)", fontSize: 13, color: "var(--ink)", fontWeight: 600 }}>
            {it.workout}
          </div>
          <div style={{
            fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 12,
            color: "var(--ink-2)", marginTop: 2, lineHeight: 1.4,
          }}>{it.adj}</div>
        </div>
      </div>
    ))}
  </div>
);

/* ── DATA QUALITY ────────────────────────────────────────────────── */

const DataQuality = ({ items }) => (
  <div style={{
    display: "grid", gridTemplateColumns: "1fr 1fr", gap: 0,
    marginTop: 8, border: "1px solid var(--rule)", borderRadius: 8,
  }}>
    {items.map((it, i) => {
      const col = it.tone === "warn" ? "var(--coral)" : it.tone === "ok" ? "var(--ink)" : "var(--ink-2)";
      const borderRight = i % 2 === 0 ? "1px solid var(--rule)" : "0";
      const borderBottom = i < 2 ? "1px solid var(--rule)" : "0";
      return (
        <div key={i} style={{
          padding: "12px 12px",
          borderRight, borderBottom,
          display: "flex", flexDirection: "column", gap: 4,
        }}>
          <span style={{
            fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-2)",
            letterSpacing: "0.10em", textTransform: "uppercase",
          }}>{it.lbl}</span>
          <span style={{
            fontFamily: "var(--font-mono)", fontWeight: 600, fontSize: 17, color: col,
            fontVariantNumeric: "tabular-nums",
          }}>{it.val}</span>
          <span style={{
            fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)",
            letterSpacing: "0.10em", textTransform: "uppercase",
          }}>{it.sub}</span>
        </div>
      );
    })}
  </div>
);

/* ════════════════════════════════════════════════════════════════════
   MAIN SCREEN
   ════════════════════════════════════════════════════════════════════ */

const FitnessPredictorScreen = ({ data, onClose }) => {
  const d = data;
  const [expanded, setExpanded] = useState(d.predictions ? d.predictions[d.predictions.length - 1].id : null);

  return (
    <div className="page">
      <PlateStrip surface="FITNESS PREDICTOR · FORWARD READ" fig="FIG. 29" />
      <div className="page__body">
        {/* top nav row */}
        <div style={{ display: "flex", justifyContent: "space-between", paddingBottom: 4 }}>
          {onClose
            ? <a className="link" onClick={onClose} style={{ fontSize: 13 }}>Close</a>
            : <Eyebrow>PREDICTOR</Eyebrow>}
          <Eyebrow>{d.status}</Eyebrow>
        </div>

        {/* date header */}
        <div className="section section--first" style={{ marginTop: 8 }}>
          <Eyebrow coral>{d.date.eyebrow}</Eyebrow>
          <h1 className="h-display" style={{ fontSize: 32, marginTop: 2 }}>{d.date.title}</h1>
        </div>

        {/* HEADLINE — one tight sentence */}
        {d.headline && (
          <p style={{
            fontFamily: "var(--font-body)", fontSize: 16, color: "var(--ink)",
            lineHeight: 1.5, marginTop: 14, marginBottom: 0,
          }}>{d.headline.text}</p>
        )}

        {/* EMPTY STATE branch */}
        {d.emptyState && (
          <>
            <div style={{ height: 18 }} />
            <EditorialRule />
            <div className="section" style={{ marginTop: 16 }}>
              <Eyebrow coral>{d.emptyState.eyebrow}</Eyebrow>
              <p style={{
                fontFamily: "var(--font-body)", fontSize: 15, color: "var(--ink)",
                lineHeight: 1.55, margin: "6px 0 14px 0",
              }}>{d.emptyState.body}</p>
              <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
                {d.emptyState.actions.map((a, i) => (
                  <button key={i} className={"btn " + (i === 0 ? "btn--primary" : "btn--secondary")}>{a}</button>
                ))}
              </div>
            </div>
          </>
        )}

        {/* ANCHOR */}
        {d.anchor && (
          <>
            <div style={{ height: 18 }} />
            <EditorialRule />
            <div style={{ height: 14 }} />
            <AnchorCard a={d.anchor} />
          </>
        )}

        {/* 5 PREDICTIONS */}
        {d.predictions && (
          <Section eyebrow="PREDICTED TIMES" eyebrowRight="TAP FOR DETAIL">
            <div style={{ marginTop: 4 }}>
              {d.predictions.map(p => (
                <PredictionRow
                  key={p.id}
                  p={p}
                  expanded={expanded === p.id}
                  onToggle={() => setExpanded(expanded === p.id ? null : p.id)}
                />
              ))}
            </div>
            <p style={{
              fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 11,
              color: "var(--ink-3)", marginTop: 8, marginBottom: 0,
            }}>
              ◆ personal best · band shows where the time lives 80% of the time, off today’s fitness.
            </p>
          </Section>
        )}

        {/* GOAL vs CURRENT */}
        {d.goal && (
          <>
            <div style={{ height: 22 }} />
            <Section eyebrow="GOAL vs CURRENT" eyebrowRight={d.goal.race}>
              <GoalVsCurrent g={d.goal} />
            </Section>
          </>
        )}

        {/* WHAT WOULD SHARPEN */}
        {d.softSpot && (
          <>
            <div style={{ height: 22 }} />
            <Section eyebrow="WHAT WOULD SHARPEN">
              <SoftSpot items={d.softSpot.items} />
            </Section>
          </>
        )}

        {/* TRAJECTORY */}
        {d.trajectory && (
          <>
            <div style={{ height: 24 }} />
            <Section eyebrow="TRAJECTORY · 9 WEEKS" eyebrowRight={d.trajectory.deltaText}>
              <div style={{ marginTop: 8 }}>
                <Trajectory t={d.trajectory} />
              </div>
            </Section>
          </>
        )}

        {/* CONTEXT LOG */}
        {d.contextLog && (
          <>
            <div style={{ height: 22 }} />
            <Section eyebrow="CONTEXT · ADJUSTMENTS APPLIED">
              <ContextLog items={d.contextLog} />
            </Section>
          </>
        )}

        {/* DATA QUALITY */}
        {d.dataQuality && (
          <>
            <div style={{ height: 22 }} />
            <Section eyebrow="DATA QUALITY">
              <DataQuality items={d.dataQuality} />
            </Section>
          </>
        )}

        <div style={{ height: 28 }} />
      </div>
    </div>
  );
};

window.FitnessPredictorScreen = FitnessPredictorScreen;

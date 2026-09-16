/* global React, window, PlateStrip, Eyebrow, EditorialRule, EvidenceChip, CoachByline, AskBar */
/* ════════════════════════════════════════════════════════════════════
   DIRECTION B · BRIEFING
   Decisive. Today's call up top, then the small set of decisions
   waiting on you, each with the coach's reasoning + cited evidence.
   Chat is the fallback ("push back, ask, change something"), not the
   primary surface.
   ════════════════════════════════════════════════════════════════════ */

const DecisionCard = ({ d, workouts }) => {
  const [picked, setPicked] = React.useState(null);
  return (
    <div style={{
      background: "var(--card)",
      borderRadius: 10,
      padding: "14px 14px 12px 14px",
      boxShadow: "0 2px 8px rgba(0,0,0,0.05)",
      display: "flex", flexDirection: "column", gap: 10,
      borderLeft: "2px solid var(--coral)",
    }}>
      <div style={{
        display: "flex", justifyContent: "space-between", alignItems: "baseline",
      }}>
        <span style={{
          fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 17,
          color: "var(--ink)", letterSpacing: "-0.005em", lineHeight: 1.25,
          flex: 1,
        }}>{d.question}</span>
        <span style={{
          fontFamily: "var(--font-mono)", fontSize: 9, fontWeight: 600,
          letterSpacing: "0.14em", color: "var(--coral)",
          whiteSpace: "nowrap", marginLeft: 10,
        }}>{d.urgency}</span>
      </div>

      <p className="coach-quote" style={{
        fontSize: 13, lineHeight: 1.5, margin: 0, color: "var(--ink-2)",
      }}>{d.because}</p>

      {d.evidence && d.evidence.length > 0 && (
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
          {d.evidence.map(eid => (
            <EvidenceChip key={eid} w={workouts[eid]} inline />
          ))}
        </div>
      )}

      <div style={{
        display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8,
        paddingTop: 4,
      }}>
        <button
          onClick={() => setPicked("rec")}
          style={{
            fontFamily: "var(--font-display)", fontSize: 12, fontWeight: 600,
            letterSpacing: "0.04em",
            padding: "9px 10px",
            borderRadius: 8, border: "0", cursor: "pointer",
            background: picked === "rec" ? "var(--coral-deep)" : "var(--coral)",
            color: "#fff",
            transition: "background .15s",
          }}>
          ✓ {d.recommend}
        </button>
        <button
          onClick={() => setPicked("alt")}
          style={{
            fontFamily: "var(--font-display)", fontSize: 12, fontWeight: 600,
            letterSpacing: "0.04em",
            padding: "9px 10px",
            borderRadius: 8,
            border: picked === "alt" ? "1.5px solid var(--ink)" : "1px solid var(--rule)",
            cursor: "pointer",
            background: "transparent",
            color: "var(--ink)",
          }}>
          {d.alt}
        </button>
      </div>
    </div>
  );
};

const CoachScreenBriefing = ({ data, workouts }) => {
  const d = data;
  return (
    <div className="page">
      <PlateStrip surface={d.plate.surface} fig={d.plate.fig} />
      <div className="page__body" style={{ padding: 0, display: "flex", flexDirection: "column" }}>
        <div style={{ padding: "14px 20px 4px 20px", flex: 1, overflowY: "auto" }}>

          {/* dateline */}
          <div style={{
            display: "flex", justifyContent: "space-between",
            alignItems: "baseline", paddingBottom: 12,
            borderBottom: "1px solid var(--rule)",
          }}>
            <span className="caption">{COACH_FIXTURES.dateline}</span>
            <span className="caption" style={{ color: "var(--ink-3)" }}>↗ THE READ</span>
          </div>

          {/* today's call */}
          <div style={{ marginTop: 16 }}>
            <CoachByline eyebrow={d.eyebrow} />
            <h1 className="h-display" style={{
              fontSize: 28, marginTop: 12, lineHeight: 1.08,
              letterSpacing: "-0.015em",
            }}>{d.call}</h1>
            <p style={{
              fontFamily: "var(--font-body)", fontStyle: "italic",
              fontSize: 14, color: "var(--ink-2)",
              margin: "8px 0 0 0", lineHeight: 1.5,
            }}>{d.callSub}</p>
          </div>

          {/* what i'm seeing — three stat tiles */}
          <div style={{ marginTop: 22 }}>
            <Eyebrow>WHAT I'M SEEING</Eyebrow>
            <div style={{
              display: "grid", gridTemplateColumns: "1fr 1fr 1fr",
              gap: 8, marginTop: 8,
            }}>
              {d.seeing.map((s, i) => (
                <div key={i} style={{
                  background: "var(--paper-elevated)",
                  border: "1px solid var(--rule)",
                  borderRadius: 8,
                  padding: "10px 10px",
                  display: "flex", flexDirection: "column", gap: 4,
                }}>
                  <span style={{
                    fontFamily: "var(--font-mono)", fontSize: 9,
                    color: "var(--ink-2)", letterSpacing: "0.12em",
                  }}>{s.lbl}</span>
                  <span style={{
                    fontFamily: "var(--font-mono)", fontWeight: 600,
                    fontSize: 18, color: "var(--ink)",
                    fontVariantNumeric: "tabular-nums", lineHeight: 1,
                  }}>{s.val}</span>
                  <span style={{
                    fontFamily: "var(--font-mono)", fontSize: 9,
                    color: "var(--ink-3)", letterSpacing: "0.08em",
                  }}>{s.sub}</span>
                </div>
              ))}
            </div>
          </div>

          {/* decisions waiting */}
          <div style={{ marginTop: 24 }}>
            <div style={{
              display: "flex", justifyContent: "space-between", alignItems: "baseline",
              marginBottom: 8,
            }}>
              <Eyebrow coral>DECISIONS WAITING · {d.decisions.length}</Eyebrow>
              <Eyebrow style={{ color: "var(--ink-3)" }}>TAP TO COMMIT</Eyebrow>
            </div>

            <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
              {d.decisions.map(dd => (
                <DecisionCard key={dd.id} d={dd} workouts={workouts} />
              ))}
            </div>
          </div>

          {/* flag */}
          {d.flag && (
            <div style={{
              marginTop: 22,
              padding: "12px 14px",
              border: "1px dashed var(--coral)",
              borderRadius: 8,
              background: "rgba(212,89,42,0.04)",
            }}>
              <span style={{
                fontFamily: "var(--font-mono)", fontSize: 9, fontWeight: 600,
                letterSpacing: "0.14em", color: "var(--coral)",
              }}>{d.flag.label}</span>
              <p className="coach-quote" style={{
                fontSize: 13, lineHeight: 1.5,
                margin: "6px 0 0 0", color: "var(--ink)",
                borderLeft: "0", paddingLeft: 0,
              }}>{d.flag.body}</p>
            </div>
          )}

          <div style={{ height: 14 }} />
        </div>

        <AskBar placeholder={d.ask} />
      </div>
    </div>
  );
};

window.CoachScreenBriefing = CoachScreenBriefing;

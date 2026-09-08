/* global React, window, PlateStrip, Eyebrow, EvidenceChip, CoachByline, CoachQuote, AskBar */
/* ════════════════════════════════════════════════════════════════════
   DIRECTION C · THREAD, REFINED
   Chat that's actually a chat. But: pinned to a single topic, with
   evidence cited inline in coach bubbles, and a strip of other open
   threads at the bottom — so the page never feels like a generic
   one-window AI assistant.
   ════════════════════════════════════════════════════════════════════ */

const Bubble = ({ m, workouts }) => {
  const isCoach = m.role === "coach";
  const wo = m.workout ? workouts[m.workout] : null;
  return (
    <div style={{
      display: "flex", flexDirection: "column",
      alignItems: isCoach ? "stretch" : "flex-end",
      gap: 4,
    }}>
      <span style={{
        fontFamily: "var(--font-mono)", fontSize: 9, fontWeight: 500,
        letterSpacing: "0.10em", color: "var(--ink-3)",
        textTransform: "uppercase",
      }}>
        {isCoach ? "COACH" : "YOU"} · {m.ts}
      </span>
      {isCoach ? (
        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
          <CoachQuote>{m.text}</CoachQuote>
          {wo && (
            <div style={{ marginLeft: 12, maxWidth: 280 }}>
              <EvidenceChip w={wo} />
            </div>
          )}
        </div>
      ) : (
        <div style={{
          maxWidth: "84%",
          background: "var(--ink)",
          color: "var(--paper)",
          fontFamily: "var(--font-body)", fontSize: 14, lineHeight: 1.5,
          padding: "9px 13px",
          borderRadius: "14px 14px 4px 14px",
        }}>{m.text}</div>
      )}
    </div>
  );
};

const CoachScreenThread = ({ data, workouts }) => {
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
            <span className="caption" style={{ color: "var(--ink-3)" }}>↗ ALL THREADS</span>
          </div>

          {/* topic header — the thing this thread is pinned to */}
          <div style={{
            marginTop: 16, paddingBottom: 14,
            borderBottom: "1px solid var(--rule)",
          }}>
            <div style={{
              display: "flex", justifyContent: "space-between",
              alignItems: "baseline",
            }}>
              <Eyebrow coral>{d.topic.eyebrow}</Eyebrow>
              <Eyebrow style={{ color: "var(--ink-3)" }}>PIN ◆</Eyebrow>
            </div>
            <h1 className="h-display" style={{
              fontSize: 24, marginTop: 6, lineHeight: 1.1,
              letterSpacing: "-0.01em",
            }}>{d.topic.title}</h1>
            <span style={{
              fontFamily: "var(--font-mono)", fontSize: 9,
              letterSpacing: "0.12em", color: "var(--ink-3)",
              textTransform: "uppercase",
              display: "block", marginTop: 6,
            }}>{d.topic.meta}</span>
          </div>

          {/* messages */}
          <div style={{
            display: "flex", flexDirection: "column",
            gap: 16, padding: "16px 0",
          }}>
            {d.messages.map((m, i) => (
              <Bubble key={i} m={m} workouts={workouts} />
            ))}
          </div>

          {/* suggested next — grounded suggestions, each with a numbered note */}
          <div style={{
            paddingTop: 14, borderTop: "1px solid var(--rule)",
            marginBottom: 18,
          }}>
            <Eyebrow>SUGGESTED · GROUNDED IN YOUR DATA</Eyebrow>
            <div style={{ display: "flex", flexDirection: "column", gap: 8, marginTop: 8 }}>
              {d.suggested.map((s, i) => (
                <div key={i} style={{
                  display: "grid", gridTemplateColumns: "1fr auto",
                  gap: 10, padding: "10px 12px",
                  background: "var(--paper-elevated)",
                  border: "1px solid var(--rule)",
                  borderRadius: 8,
                  alignItems: "baseline",
                  cursor: "pointer",
                }}>
                  <div>
                    <div style={{
                      fontFamily: "var(--font-body)", fontSize: 13.5,
                      color: "var(--ink)", lineHeight: 1.4,
                    }}>{s.text}</div>
                    <div style={{
                      fontFamily: "var(--font-mono)", fontSize: 10,
                      color: "var(--ink-2)", letterSpacing: "0.06em",
                      marginTop: 3,
                    }}>{s.note}</div>
                  </div>
                  <span style={{
                    fontFamily: "var(--font-mono)", fontSize: 12,
                    color: "var(--coral)",
                  }}>→</span>
                </div>
              ))}
            </div>
          </div>

          {/* other open threads */}
          <div style={{
            paddingTop: 14, paddingBottom: 8,
            borderTop: "1px solid var(--rule)",
          }}>
            <Eyebrow>OTHER OPEN · {d.otherThreads.length}</Eyebrow>
            <div style={{
              display: "flex", gap: 6, overflowX: "auto",
              paddingTop: 10, paddingBottom: 4,
            }}>
              {d.otherThreads.map(t => (
                <div key={t.id} style={{
                  flex: "0 0 auto",
                  padding: "8px 12px",
                  border: "1px solid var(--rule)",
                  borderRadius: 8, background: "var(--card)",
                  display: "flex", flexDirection: "column", gap: 3,
                  minWidth: 110,
                  cursor: "pointer",
                }}>
                  <span style={{
                    fontFamily: "var(--font-display)", fontWeight: 600,
                    fontSize: 13, color: "var(--ink)",
                    letterSpacing: "-0.005em",
                  }}>{t.title}</span>
                  <span style={{
                    fontFamily: "var(--font-mono)", fontSize: 9,
                    color: "var(--ink-3)", letterSpacing: "0.10em",
                  }}>{t.count} MSG · {t.last}</span>
                </div>
              ))}
            </div>
          </div>

          <div style={{ height: 10 }} />
        </div>

        <AskBar
          placeholder="Reply about Wednesday's MP block…"
          chips={d.suggested.map(s => s.text)}
        />
      </div>
    </div>
  );
};

window.CoachScreenThread = CoachScreenThread;

/* global React, window, PlateStrip, Eyebrow, EditorialRule, EvidenceChip, DocChip, ProseSegment, CoachByline, ConfidenceBar, AskBar, COACH_FIXTURES */
/* ════════════════════════════════════════════════════════════════════
   DIRECTION A · THE READ  (canonical)

   Editorial first. A signed paragraph the coach posted this morning,
   citing actual workouts (◆ coral chips) AND knowledge-base docs
   (§ outlined chips) inline in the prose. Below the read:
   - WHAT I CAN'T SEE  (honest-when-uncertain block)
   - SOURCES expander (every workout, doc, and memo that fed the read)
   - CONFIDENCE bar
   - OPEN THREADS list
   - ASK bar at the bottom

   Chat is one tool, not the surface. When you ask something, the
   reply itself becomes editorial — see `coach-ios-read-reply.jsx`
   or the `readReply` fixture used inline below.
   ════════════════════════════════════════════════════════════════════ */

const SourcesPanel = ({ sources, workouts, docs }) => {
  const [open, setOpen] = React.useState(false);
  return (
    <div>
      <div
        onClick={() => setOpen(!open)}
        style={{
          display: "flex", justifyContent: "space-between", alignItems: "baseline",
          padding: "10px 0",
          borderTop: "1px solid var(--rule)",
          borderBottom: open ? "0" : "1px solid var(--rule)",
          cursor: "pointer",
        }}
      >
        <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
          <span style={{
            fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 500,
            letterSpacing: "0.14em", color: "var(--ink)",
            textTransform: "uppercase",
          }}>{sources.label}</span>
          <span style={{
            fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)",
            letterSpacing: "0.10em",
          }}>{sources.sub}</span>
        </div>
        <span style={{
          fontFamily: "var(--font-mono)", fontSize: 14, color: "var(--ink-3)",
          transform: open ? "rotate(90deg)" : "none",
          transition: "transform .2s",
        }}>›</span>
      </div>
      {open && (
        <div style={{
          padding: "10px 0 14px 0",
          borderBottom: "1px solid var(--rule)",
          display: "flex", flexDirection: "column", gap: 8,
        }}>
          {sources.items.map((it, i) => {
            if (it.kind === "workout") {
              return <EvidenceChip key={i} w={workouts[it.id]} />;
            }
            if (it.kind === "doc") {
              return <DocChip key={i} d={docs[it.id]} />;
            }
            if (it.kind === "memo") {
              return (
                <div key={i} style={{
                  padding: "8px 10px",
                  border: "1px solid var(--rule)",
                  borderRadius: 6,
                  background: "var(--paper)",
                  display: "flex", flexDirection: "column", gap: 4,
                  cursor: "pointer",
                }}>
                  <span style={{
                    fontFamily: "var(--font-mono)", fontSize: 9, fontWeight: 600,
                    letterSpacing: "0.14em", color: "var(--ink-2)",
                  }}>♪ {it.label}</span>
                  <span style={{
                    fontFamily: "var(--font-body)", fontStyle: "italic",
                    fontSize: 12, color: "var(--ink)", lineHeight: 1.4,
                  }}>{it.excerpt}</span>
                </div>
              );
            }
            return null;
          })}
        </div>
      )}
    </div>
  );
};

const CantSeeBlock = ({ block }) => (
  <div style={{
    margin: "16px 0",
    padding: "12px 14px",
    background: "var(--paper-elevated)",
    borderLeft: "2px solid var(--ink-3)",
  }}>
    <span style={{
      fontFamily: "var(--font-mono)", fontSize: 9, fontWeight: 600,
      letterSpacing: "0.14em", color: "var(--ink-2)",
    }}>{block.eyebrow}</span>
    <p style={{
      fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13.5,
      color: "var(--ink)", lineHeight: 1.5,
      margin: "6px 0 0 0",
    }}>{block.body}</p>
  </div>
);

/* ── THE READ · default state (this morning's post) ──────────────── */
const CoachScreenRead = ({ data, workouts, docs }) => {
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
            <span className="caption" style={{ color: "var(--ink-3)" }}>↗ HISTORY</span>
          </div>

          {/* byline */}
          <div style={{ marginTop: 16 }}>
            <CoachByline eyebrow={d.eyebrow} />
          </div>

          {/* headline */}
          <h1 className="h-display" style={{
            fontSize: 32, marginTop: 14, lineHeight: 1.02,
            letterSpacing: "-0.015em",
          }}>{d.headline}</h1>

          {/* paragraph with inline workout + doc chips */}
          <p style={{
            fontFamily: "var(--font-body)", fontSize: 16,
            color: "var(--ink)", lineHeight: 1.6,
            marginTop: 16, marginBottom: 0,
          }}>
            <ProseSegment segments={d.paragraph} workouts={workouts} docs={docs} />
          </p>

          {/* signature */}
          <p style={{
            fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 12,
            color: "var(--ink-3)", marginTop: 14, marginBottom: 0,
          }}>{d.signature}</p>

          {/* what i can't see — the honesty block */}
          {d.cantSee && <CantSeeBlock block={d.cantSee} />}

          {/* sources expander */}
          {d.sources && (
            <div style={{ marginTop: 6 }}>
              <SourcesPanel sources={d.sources} workouts={workouts} docs={docs} />
            </div>
          )}

          {/* confidence */}
          <div style={{ paddingTop: 14, paddingBottom: 6 }}>
            <ConfidenceBar
              label={d.confidence.label}
              level={d.confidence.level}
              sub={d.confidence.sub}
            />
          </div>

          {/* editorial rule break */}
          <div style={{ margin: "20px 0 16px 0" }}>
            <EditorialRule />
          </div>

          {/* open threads */}
          {d.threads && (
            <div>
              <div style={{
                display: "flex", justifyContent: "space-between",
                alignItems: "baseline", marginBottom: 4,
              }}>
                <Eyebrow>OPEN THREADS</Eyebrow>
                <Eyebrow style={{ color: "var(--ink-3)" }}>{d.threads.length} OPEN</Eyebrow>
              </div>

              {d.threads.map(t => (
                <div key={t.id} style={{
                  padding: "14px 0",
                  borderBottom: "1px solid var(--rule)",
                  display: "grid", gridTemplateColumns: "1fr auto", gap: 10,
                  alignItems: "baseline",
                  cursor: "pointer",
                }}>
                  <div>
                    <div style={{
                      display: "flex", alignItems: "baseline", gap: 8, marginBottom: 6,
                    }}>
                      <span style={{
                        fontFamily: "var(--font-display)", fontWeight: 700,
                        fontSize: 17, color: "var(--ink)", letterSpacing: "-0.005em",
                      }}>{t.title}</span>
                      {t.unread > 0 && (
                        <span style={{
                          display: "inline-block", width: 6, height: 6,
                          background: "var(--coral)", borderRadius: 999,
                        }} />
                      )}
                    </div>
                    <p className="coach-quote" style={{
                      fontSize: 13, lineHeight: 1.45, color: "var(--ink-2)",
                      margin: 0,
                    }}>{t.coachLine}</p>
                  </div>
                  <span style={{
                    fontFamily: "var(--font-mono)", fontSize: 9,
                    color: "var(--ink-3)", letterSpacing: "0.10em",
                    whiteSpace: "nowrap",
                  }}>{t.last}</span>
                </div>
              ))}
            </div>
          )}

          <div style={{ height: 12 }} />
        </div>

        <AskBar chips={d.askChips} placeholder="Ask anything you're chewing on…" />
      </div>
    </div>
  );
};

/* ── THE READ · reply state ──────────────────────────────────────────
   What happens after you ask a question. The reply itself is
   editorial — same byline/headline/prose/citations/confidence
   treatment as a morning post. Reinforces "coach, not chat." */
const CoachScreenReadReply = ({ data, workouts, docs }) => {
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
            <span className="caption" style={{ color: "var(--ink-3)" }}>↗ BACK TO READ</span>
          </div>

          {/* what YOU asked */}
          <div style={{ marginTop: 16, marginBottom: 4 }}>
            <span style={{
              fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 500,
              letterSpacing: "0.14em", color: "var(--ink-2)",
              textTransform: "uppercase",
            }}>{d.you.eyebrow}</span>
            <p style={{
              fontFamily: "var(--font-display)", fontStyle: "italic",
              fontWeight: 400, fontSize: 22,
              color: "var(--ink-2)", lineHeight: 1.25,
              margin: "6px 0 0 0", letterSpacing: "-0.005em",
            }}>"{d.you.text}"</p>
          </div>

          {/* editorial rule */}
          <div style={{ margin: "18px 0 14px 0" }}>
            <EditorialRule />
          </div>

          {/* byline */}
          <CoachByline eyebrow={d.eyebrow} />

          {/* headline (the answer's lede) */}
          <h1 className="h-display" style={{
            fontSize: 26, marginTop: 12, lineHeight: 1.08,
            letterSpacing: "-0.015em",
          }}>{d.headline}</h1>

          {/* the paragraph reply — workouts + docs cited inline */}
          <p style={{
            fontFamily: "var(--font-body)", fontSize: 15.5,
            color: "var(--ink)", lineHeight: 1.6,
            marginTop: 14, marginBottom: 0,
          }}>
            <ProseSegment segments={d.paragraph} workouts={workouts} docs={docs} />
          </p>

          {/* signature — note the model attribution */}
          <p style={{
            fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 12,
            color: "var(--ink-3)", marginTop: 12, marginBottom: 14,
          }}>{d.signature}</p>

          {/* confidence */}
          <div style={{
            paddingTop: 12, paddingBottom: 6,
            borderTop: "1px solid var(--rule)",
          }}>
            <ConfidenceBar
              label={d.confidence.label}
              level={d.confidence.level}
              sub={d.confidence.sub}
            />
          </div>

          {/* related next questions, grounded */}
          <div style={{ marginTop: 22 }}>
            <Eyebrow>RELATED · ASK NEXT</Eyebrow>
            <div style={{ display: "flex", flexDirection: "column", gap: 6, marginTop: 8 }}>
              {d.relatedAsk.map((q, i) => (
                <div key={i} style={{
                  display: "flex", justifyContent: "space-between", alignItems: "baseline",
                  padding: "10px 12px",
                  border: "1px solid var(--rule)",
                  borderRadius: 6, background: "var(--paper)",
                  cursor: "pointer",
                }}>
                  <span style={{
                    fontFamily: "var(--font-body)", fontSize: 13.5,
                    color: "var(--ink)",
                  }}>{q}</span>
                  <span style={{
                    fontFamily: "var(--font-mono)", fontSize: 12, color: "var(--coral)",
                  }}>→</span>
                </div>
              ))}
            </div>
          </div>

          <div style={{ height: 12 }} />
        </div>

        <AskBar placeholder="Keep going…" />
      </div>
    </div>
  );
};

window.CoachScreenRead = CoachScreenRead;
window.CoachScreenReadReply = CoachScreenReadReply;

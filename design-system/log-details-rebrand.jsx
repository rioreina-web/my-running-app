/* global React, Eyebrow, Hairline, MoodPill */
/* ════════════════════════════════════════════════════════════════════
   LOG DETAILS · BRAND REBRAND
   Three directions for the post-run log detail sheet. All three:
   • kill card-in-card (rounded white shells inside paper)
   • kill the off-palette tiles (mint linked-workout, pink coach CTA, red delete)
   • replace the "Distance: 6.9 mi / Duration: 51:06 / …" serif paragraph
     with mono tabular numerals
   • restrict coral to one hit per cluster
   ════════════════════════════════════════════════════════════════════ */

const { useState } = React;

/* ── shared tokens for inline styles ─────────────────────────────── */

const ldStyles = {
  paper: { background: "var(--paper)", color: "var(--ink)" },
  mono: {
    fontFamily: "var(--font-mono)",
    fontVariantNumeric: "tabular-nums",
  },
  monoEyebrow: {
    fontFamily: "var(--font-mono)",
    fontSize: 10,
    fontWeight: 500,
    letterSpacing: "0.14em",
    textTransform: "uppercase",
    color: "var(--ink-2)",
  },
  monoEyebrowSm: {
    fontFamily: "var(--font-mono)",
    fontSize: 9,
    fontWeight: 500,
    letterSpacing: "0.12em",
    textTransform: "uppercase",
    color: "var(--ink-3)",
  },
  italic: {
    fontFamily: "var(--font-body)",
    fontStyle: "italic",
    color: "var(--ink-2)",
    lineHeight: 1.55,
  },
};

/* ════════════════════════════════════════════════════════════════════
   DIRECTION A · "EDITORIAL"
   The whole sheet is hairlines + plates. Nothing has a card shell.
   ════════════════════════════════════════════════════════════════════ */

function LogDetailsEditorial() {
  return (
    <div style={{ ...ldStyles.paper, height: "100%", display: "flex", flexDirection: "column", overflow: "hidden" }}>
      {/* Plate strip */}
      <div style={{
        display: "flex", justifyContent: "space-between",
        padding: "14px 24px 0 24px",
      }}>
        <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
          <span style={{ ...ldStyles.monoEyebrow, color: "var(--ink)" }}>RUNNING LOG</span>
          <span style={ldStyles.monoEyebrow}>— JOURNAL · ENTRY DETAIL</span>
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 2, textAlign: "right" }}>
          <span style={{ ...ldStyles.monoEyebrow, color: "var(--ink)" }}>05.21.26</span>
          <span style={ldStyles.monoEyebrow}>09:06</span>
        </div>
      </div>

      <div style={{ flex: 1, overflowY: "auto", padding: "8px 0 32px 0" }}>
        {/* Top rule + actions row */}
        <div style={{
          padding: "0 24px",
          display: "flex", justifyContent: "space-between", alignItems: "baseline",
          marginTop: 14,
        }}>
          <span style={{ ...ldStyles.monoEyebrow, color: "var(--coral)", cursor: "pointer" }}>EDIT</span>
          <span style={ldStyles.monoEyebrow}>DONE</span>
        </div>
        <Hairline style={{ margin: "10px 24px 0 24px", width: "auto" }} />

        {/* Day heading — editorial */}
        <div style={{ padding: "26px 24px 0 24px" }}>
          <h1 style={{
            fontFamily: "var(--font-display)",
            fontWeight: 700, fontSize: 44, color: "var(--ink)",
            margin: 0, letterSpacing: "-0.01em", lineHeight: 1,
          }}>Thursday</h1>
          <p style={{ ...ldStyles.italic, fontSize: 13, color: "var(--ink-3)", margin: "8px 0 0 0" }}>
            — a quiet 51 minutes before the day started. —
          </p>
        </div>

        {/* Stat strip — replaces both "Original Notes" paragraph AND linked-workout tile */}
        <div style={{
          margin: "22px 24px 0 24px",
          display: "grid",
          gridTemplateColumns: "repeat(5, 1fr)",
          borderTop: "1px solid var(--rule)",
          borderBottom: "1px solid var(--rule)",
        }}>
          {[
            { l: "DIST", v: "6.9", u: "mi" },
            { l: "TIME", v: "51:06" },
            { l: "PACE", v: "7:24", u: "/mi" },
            { l: "HR",   v: "143", u: "bpm" },
            { l: "ELEV", v: "43",  u: "m" },
          ].map((s, i, arr) => (
            <div key={s.l} style={{
              padding: "12px 8px",
              borderRight: i < arr.length - 1 ? "1px solid var(--rule)" : "none",
              display: "flex", flexDirection: "column", alignItems: "center", gap: 6,
            }}>
              <span style={ldStyles.monoEyebrowSm}>{s.l}</span>
              <span style={{ ...ldStyles.mono, fontSize: 18, fontWeight: 600, color: "var(--ink)" }}>
                {s.v}{s.u && <span style={{ fontSize: 10, color: "var(--ink-3)", marginLeft: 2 }}>{s.u}</span>}
              </span>
            </div>
          ))}
        </div>

        {/* Linked workout — quiet hairline cell, no mint fill */}
        <div style={{
          margin: "0 24px",
          padding: "10px 0",
          borderBottom: "1px solid var(--rule)",
          display: "flex", justifyContent: "space-between", alignItems: "baseline",
        }}>
          <span style={ldStyles.monoEyebrow}>LINKED · HEALTHKIT · 05.21 9:06</span>
          <span style={{ ...ldStyles.monoEyebrow, color: "var(--coral)", cursor: "pointer" }}>VIEW DETAIL ↗</span>
        </div>

        {/* AI Summary — eyebrow + italic body, no outlined card */}
        <div style={{ padding: "22px 24px 0 24px" }}>
          <Eyebrow>AI SUMMARY</Eyebrow>
          <p style={{
            fontFamily: "var(--font-display)", fontWeight: 600, fontSize: 22,
            color: "var(--ink)", margin: "6px 0 0 0", letterSpacing: "-0.01em",
          }}>Morning Run</p>
          <p style={{ ...ldStyles.italic, fontSize: 14, margin: "6px 0 0 0" }}>
            Steady aerobic effort. HR sat 12 bpm under your zone-2 ceiling — a true easy day.
          </p>
        </div>

        {/* Coach insight — text link, not a coral-pill button */}
        <div style={{ padding: "22px 24px 0 24px" }}>
          <Eyebrow>COACH INSIGHT</Eyebrow>
          <p style={{ ...ldStyles.italic, fontSize: 14, margin: "6px 0 0 0" }}>
            Not yet generated.
          </p>
          <a style={{
            display: "inline-block", marginTop: 8,
            fontFamily: "var(--font-display)", fontWeight: 600, fontSize: 14,
            color: "var(--coral)", borderBottom: "1px solid var(--coral)",
            paddingBottom: 2, cursor: "pointer", textDecoration: "none",
          }}>Ask the coach →</a>
        </div>

        {/* Workout notes — inline composer, no white card */}
        <div style={{
          margin: "22px 24px 0 24px",
          paddingTop: 14,
          borderTop: "1px solid var(--rule)",
        }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
            <Eyebrow>WORKOUT NOTES</Eyebrow>
            <span style={{ ...ldStyles.monoEyebrow, color: "var(--ink-3)" }}>OPTIONAL</span>
          </div>
          <textarea
            placeholder="Splits, intervals, anything worth remembering…"
            defaultValue=""
            style={{
              width: "100%", minHeight: 64, marginTop: 8,
              background: "transparent", border: 0, outline: "none", resize: "none",
              fontFamily: "var(--font-body)", fontStyle: "italic",
              fontSize: 15, lineHeight: 1.5, color: "var(--ink)",
              padding: 0, boxSizing: "border-box",
            }}
          />
          <div style={{ display: "flex", justifyContent: "flex-end" }}>
            <span style={{ ...ldStyles.monoEyebrow, color: "var(--ink-3)", cursor: "default" }}>SAVE</span>
          </div>
        </div>

        {/* Footer: quiet destructive */}
        <div style={{
          margin: "32px 24px 0 24px", paddingTop: 14,
          borderTop: "1px solid var(--rule)",
          display: "flex", justifyContent: "space-between", alignItems: "baseline",
        }}>
          <span style={{ ...ldStyles.italic, fontSize: 12, color: "var(--ink-3)" }}>
            — Logged manually, May 21. —
          </span>
          <span style={{ ...ldStyles.monoEyebrow, color: "var(--ink-3)", cursor: "pointer" }}>DELETE LOG</span>
        </div>
      </div>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   DIRECTION B · "RECEIPT"
   Treats the entry as a printed receipt: top eyebrows, big readout
   block, italic note, then quiet metadata at the foot.
   ════════════════════════════════════════════════════════════════════ */

function LogDetailsReceipt() {
  return (
    <div style={{ ...ldStyles.paper, height: "100%", display: "flex", flexDirection: "column", overflow: "hidden" }}>
      {/* Plate strip */}
      <div style={{
        display: "flex", justifyContent: "space-between",
        padding: "14px 24px 0 24px",
      }}>
        <span style={{ ...ldStyles.monoEyebrow, color: "var(--ink)" }}>RUNNING LOG</span>
        <span style={ldStyles.monoEyebrow}>RECEIPT · 05.21.26</span>
      </div>

      <div style={{ flex: 1, overflowY: "auto", padding: "12px 0 32px 0" }}>
        {/* Actions row */}
        <div style={{
          padding: "6px 24px 14px 24px",
          display: "flex", justifyContent: "space-between", alignItems: "baseline",
          borderBottom: "1px solid var(--rule)",
        }}>
          <span style={{ ...ldStyles.monoEyebrow, color: "var(--coral)", cursor: "pointer" }}>EDIT</span>
          <span style={ldStyles.monoEyebrow}>LOG DETAILS</span>
          <span style={ldStyles.monoEyebrow}>DONE</span>
        </div>

        {/* Headline block — single big readout, not stat tiles */}
        <div style={{ padding: "28px 24px 0 24px", textAlign: "center" }}>
          <span style={ldStyles.monoEyebrow}>THU · 09:06 · MORNING RUN</span>
          <div style={{
            ...ldStyles.mono, fontWeight: 600, fontSize: 64,
            color: "var(--ink)", marginTop: 10, letterSpacing: "-0.02em", lineHeight: 1,
          }}>51:06</div>
          <div style={{
            ...ldStyles.mono, fontWeight: 500, fontSize: 18,
            color: "var(--ink-2)", marginTop: 8,
          }}>
            6.9 mi <span style={{ color: "var(--ink-3)" }}>·</span> 7:24 pace
          </div>
        </div>

        {/* Hairline divider, mono key:value pairs */}
        <div style={{ margin: "28px 24px 0 24px" }}>
          <div className="e-rule" style={{ marginBottom: 14 }}><span className="dot"></span></div>

          {[
            ["Heart rate", "143 bpm"],
            ["Elevation",  "43 m"],
            ["Source",     "HealthKit"],
            ["Linked",     "VIEW DETAIL ↗", true],
          ].map(([k, v, isLink], i, arr) => (
            <div key={k} style={{
              display: "flex", justifyContent: "space-between", alignItems: "baseline",
              padding: "10px 0",
              borderBottom: i < arr.length - 1 ? "1px solid var(--rule)" : "none",
            }}>
              <span style={{ ...ldStyles.monoEyebrow, color: "var(--ink-2)" }}>{k}</span>
              <span style={{
                ...ldStyles.mono, fontSize: 13, fontWeight: 600,
                color: isLink ? "var(--coral)" : "var(--ink)",
                cursor: isLink ? "pointer" : "default",
                letterSpacing: isLink ? "0.10em" : 0,
                textTransform: isLink ? "uppercase" : "none",
              }}>{v}</span>
            </div>
          ))}
        </div>

        {/* AI summary — italic, no card */}
        <div style={{
          margin: "26px 24px 0 24px", paddingTop: 14,
          borderTop: "1px solid var(--rule)",
        }}>
          <Eyebrow>THE COACH READ</Eyebrow>
          <p style={{ ...ldStyles.italic, color: "var(--ink)", fontSize: 15, margin: "8px 0 0 0" }}>
            "Steady aerobic effort — HR sat 12 bpm under your zone-2 ceiling. A true easy day,
            exactly what the plan asked for."
          </p>
          <a style={{
            display: "inline-block", marginTop: 10,
            fontFamily: "var(--font-display)", fontWeight: 600, fontSize: 14,
            color: "var(--coral)", borderBottom: "1px solid var(--coral)",
            paddingBottom: 2, cursor: "pointer", textDecoration: "none",
          }}>Ask for more detail →</a>
        </div>

        {/* Notes composer — sits at the bottom like a tear-off line */}
        <div style={{
          margin: "26px 24px 0 24px", paddingTop: 14,
          borderTop: "1px solid var(--rule)",
        }}>
          <Eyebrow>NOTES</Eyebrow>
          <textarea
            placeholder="Splits, intervals, anything worth remembering…"
            defaultValue=""
            style={{
              width: "100%", minHeight: 56, marginTop: 8,
              background: "transparent", border: 0, outline: "none", resize: "none",
              fontFamily: "var(--font-body)", fontStyle: "italic",
              fontSize: 15, lineHeight: 1.5, color: "var(--ink)",
              padding: 0, boxSizing: "border-box",
            }}
          />
        </div>

        {/* Footer */}
        <div style={{
          margin: "32px 24px 0 24px", paddingTop: 14,
          borderTop: "1px solid var(--rule)",
          display: "flex", justifyContent: "space-between", alignItems: "baseline",
        }}>
          <span style={{ ...ldStyles.italic, fontSize: 12, color: "var(--ink-3)" }}>
            — Entry #0421 · May 21, 9:06 AM. —
          </span>
          <span style={{ ...ldStyles.monoEyebrow, color: "var(--ink-3)", cursor: "pointer" }}>DELETE</span>
        </div>
      </div>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   DIRECTION C · "DENSE"
   One screen, no scrolling. Header receipt, journal-row note, coach
   inline. Closer to current architecture but cleaned up.
   ════════════════════════════════════════════════════════════════════ */

function LogDetailsDense() {
  const [notes, setNotes] = useState("");
  return (
    <div style={{ ...ldStyles.paper, height: "100%", display: "flex", flexDirection: "column", overflow: "hidden" }}>
      {/* Plate strip */}
      <div style={{
        display: "flex", justifyContent: "space-between",
        padding: "14px 24px 0 24px",
      }}>
        <span style={{ ...ldStyles.monoEyebrow, color: "var(--ink)" }}>RUNNING LOG</span>
        <span style={ldStyles.monoEyebrow}>LOG · 05.21.26</span>
      </div>

      <div style={{ flex: 1, overflowY: "auto", padding: "10px 0 32px 0" }}>
        {/* Actions row */}
        <div style={{
          padding: "8px 24px 12px 24px",
          display: "flex", justifyContent: "space-between", alignItems: "baseline",
        }}>
          <span style={{ ...ldStyles.monoEyebrow, color: "var(--coral)", cursor: "pointer" }}>EDIT</span>
          <span style={ldStyles.monoEyebrow}>DONE</span>
        </div>
        <Hairline style={{ margin: "0 24px", width: "auto" }} />

        {/* Title row: day + workout type */}
        <div style={{
          padding: "20px 24px 0 24px",
          display: "flex", justifyContent: "space-between", alignItems: "baseline",
        }}>
          <h1 style={{
            fontFamily: "var(--font-display)", fontWeight: 700,
            fontSize: 28, color: "var(--ink)", margin: 0, letterSpacing: "-0.01em",
          }}>Thursday, easy.</h1>
          <MoodPill mood="positive" />
        </div>
        <p style={{
          ...ldStyles.italic, fontSize: 12, color: "var(--ink-3)",
          margin: "6px 24px 0 24px",
        }}>— May 21 at 9:06 AM —</p>

        {/* Stat strip — replaces the duplicated stat list AND the mint linked-workout tile */}
        <div style={{
          margin: "20px 24px 0 24px",
          display: "grid",
          gridTemplateColumns: "repeat(5, 1fr)",
          borderTop: "1px solid var(--rule)",
          borderBottom: "1px solid var(--rule)",
        }}>
          {[
            { l: "MI",   v: "6.9" },
            { l: "TIME", v: "51:06" },
            { l: "PACE", v: "7:24" },
            { l: "HR",   v: "143" },
            { l: "ELEV", v: "43" },
          ].map((s, i, arr) => (
            <div key={s.l} style={{
              padding: "10px 4px",
              borderRight: i < arr.length - 1 ? "1px solid var(--rule)" : "none",
              display: "flex", flexDirection: "column", alignItems: "center", gap: 4,
            }}>
              <span style={ldStyles.monoEyebrowSm}>{s.l}</span>
              <span style={{ ...ldStyles.mono, fontSize: 18, fontWeight: 600, color: "var(--ink)" }}>{s.v}</span>
            </div>
          ))}
        </div>

        {/* Linked source — single coral hit */}
        <div style={{
          margin: "0 24px", padding: "10px 0",
          borderBottom: "1px solid var(--rule)",
          display: "flex", justifyContent: "space-between", alignItems: "baseline",
        }}>
          <span style={ldStyles.monoEyebrowSm}>SOURCE · APPLE HEALTH</span>
          <span style={{ ...ldStyles.monoEyebrowSm, color: "var(--coral)", cursor: "pointer" }}>VIEW DETAIL ↗</span>
        </div>

        {/* Coach read — italic, with quiet underline action */}
        <div style={{ padding: "20px 24px 0 24px" }}>
          <Eyebrow>THE COACH READ</Eyebrow>
          <p style={{ ...ldStyles.italic, color: "var(--ink)", fontSize: 14, margin: "8px 0 0 0" }}>
            "Steady aerobic effort — HR sat 12 bpm under your zone-2 ceiling. A true easy day."
          </p>
          <a style={{
            display: "inline-block", marginTop: 10,
            fontFamily: "var(--font-display)", fontWeight: 600, fontSize: 14,
            color: "var(--coral)", borderBottom: "1px solid var(--coral)",
            paddingBottom: 2, cursor: "pointer", textDecoration: "none",
          }}>Generate detailed feedback →</a>
        </div>

        {/* Notes — inline, no card */}
        <div style={{
          margin: "22px 24px 0 24px", paddingTop: 14,
          borderTop: "1px solid var(--rule)",
        }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
            <Eyebrow>YOUR NOTES</Eyebrow>
            <span style={{
              ...ldStyles.monoEyebrowSm,
              color: notes.trim() ? "var(--coral)" : "var(--ink-3)",
              cursor: notes.trim() ? "pointer" : "default",
            }}>SAVE</span>
          </div>
          <textarea
            placeholder="Splits, intervals, how it felt…"
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            style={{
              width: "100%", minHeight: 56, marginTop: 8,
              background: "transparent", border: 0, outline: "none", resize: "none",
              fontFamily: "var(--font-body)", fontStyle: notes ? "normal" : "italic",
              fontSize: 15, lineHeight: 1.5, color: "var(--ink)",
              padding: 0, boxSizing: "border-box",
            }}
          />
        </div>

        {/* Footer — quiet delete only */}
        <div style={{
          margin: "32px 24px 0 24px", paddingTop: 12,
          borderTop: "1px solid var(--rule)",
          display: "flex", justifyContent: "flex-end",
        }}>
          <span style={{ ...ldStyles.monoEyebrowSm, color: "var(--ink-3)", cursor: "pointer" }}>DELETE LOG</span>
        </div>
      </div>
    </div>
  );
}

/* ── export to window for the canvas ─────────────────────────────── */
Object.assign(window, {
  LogDetailsEditorial,
  LogDetailsReceipt,
  LogDetailsDense,
});

/* global React, Eyebrow, Hairline, MoodPill */
/* ════════════════════════════════════════════════════════════════════
   JOURNAL ENTRY · REDESIGN
   Brief: the current entry-detail reads like a thin data slip. Make it
   feel like a JOURNAL, put the athlete's OWN words at the center, and
   make the linked workout obvious + one tap away.

   Both directions:
   • lead with the written entry, not the AI summary
   • turn "Workout Notes: Distance 7 mi / Type: Moderate" (an auto data
     dump) into a real, reflective note the athlete writes
   • promote the faint "LINKED · STRAVA · VIEW DETAIL" hairline into a
     proper tappable linked-workout card with a route + live stats
   • keep one coral hit per cluster, hairlines + plates, no card-in-card
   ════════════════════════════════════════════════════════════════════ */

const { useState } = React;

/* ─── the entry fixture (the Tuesday run from the screenshot) ─────── */

const JR_ENTRY = {
  day: "Tuesday",
  date: "Jun 16",
  time: "6:09 PM",
  mood: "positive",
  dateline: "a humid evening seven, taken easy on purpose.",
  // The athlete's OWN words — the heart of the journal.
  note:
    "Heavy legs out the door — the first two miles were a slog in the " +
    "humidity and I almost cut it short. Found a rhythm around mile three " +
    "and the back half came easy. Kept it controlled on purpose; tomorrow's " +
    "the session that actually matters. Finished strong, and that's the part " +
    "I want to remember.",
  aiSummary:
    "A 7-mile moderate run at a comfortable, steady effort. Humidity was " +
    "noticeable but manageable — a solid aerobic day that sets up tomorrow's workout.",
  coach:
    "Great that the moderate seven felt comfortable, especially coming off a " +
    "fatigued stretch. You're primed for tomorrow — prioritise recovery and " +
    "fuelling tonight to get the most out of it.",
};

/* linked workout summary (Strava) */
const JR_WORKOUT = {
  source: "Strava",
  type: "Moderate run",
  distMi: "7.0",
  time: "53:48",
  pace: "7:41",
  hr: "146",
  at: "5:14 PM",
};

/* ─── shared inline tokens ───────────────────────────────────────── */

const jrStyles = {
  mono: { fontFamily: "var(--font-mono)", fontVariantNumeric: "tabular-nums" },
  eyebrow: {
    fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 500,
    letterSpacing: "0.14em", textTransform: "uppercase", color: "var(--ink-2)",
  },
  eyebrowSm: {
    fontFamily: "var(--font-mono)", fontSize: 9, fontWeight: 500,
    letterSpacing: "0.12em", textTransform: "uppercase", color: "var(--ink-3)",
  },
  italic: {
    fontFamily: "var(--font-body)", fontStyle: "italic",
    color: "var(--ink-2)", lineHeight: 1.55,
  },
};

/* ─── mini route glyph for the linked-workout card ───────────────── */

function MiniRoute({ w = 64, h = 64 }) {
  return (
    <div style={{
      width: w, height: h, flexShrink: 0,
      background: "var(--paper-deep)",
      border: "1px solid var(--rule)",
      position: "relative", overflow: "hidden",
    }}>
      <svg viewBox="0 0 64 64" style={{ width: "100%", height: "100%", display: "block" }}>
        <path d="M 12 50 Q 18 28, 32 32 T 48 18 Q 54 14, 52 26"
          fill="none" stroke="var(--coral)" strokeWidth="2"
          strokeLinecap="round" strokeLinejoin="round" />
        <circle cx="12" cy="50" r="3" fill="var(--ink)" />
        <circle cx="52" cy="26" r="3" fill="var(--coral)" />
      </svg>
    </div>
  );
}

/* ─── the linked-workout card — the "easy link" ──────────────────── */
/* Two visual treatments share one data layout.                       */

function LinkedWorkoutCard({ variant = "plate" }) {
  const w = JR_WORKOUT;
  const stats = [
    { l: "DIST", v: w.distMi, u: "mi" },
    { l: "TIME", v: w.time },
    { l: "PACE", v: w.pace, u: "/mi" },
    { l: "HR", v: w.hr },
  ];

  return (
    <div
      style={{
        display: "flex", alignItems: "stretch", gap: 14,
        padding: "14px 14px",
        background: variant === "plate" ? "var(--paper-elevated)" : "transparent",
        border: variant === "plate" ? "1px solid var(--rule)" : "none",
        borderTop: variant === "ledger" ? "1px solid var(--ink)" : undefined,
        borderBottom: variant === "ledger" ? "1px solid var(--rule)" : undefined,
        cursor: "pointer",
      }}
    >
      <MiniRoute w={64} h={64} />

      <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "space-between", minWidth: 0 }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
          <span style={jrStyles.eyebrowSm}>LINKED RUN · {w.source.toUpperCase()}</span>
          <span style={{ ...jrStyles.eyebrowSm }}>{w.at}</span>
        </div>

        <div style={{ display: "flex", gap: 16, marginTop: 8 }}>
          {stats.map((s) => (
            <div key={s.l} style={{ display: "flex", flexDirection: "column", gap: 3 }}>
              <span style={{ ...jrStyles.eyebrowSm, fontSize: 8 }}>{s.l}</span>
              <span style={{ ...jrStyles.mono, fontSize: 15, fontWeight: 600, color: "var(--ink)", lineHeight: 1 }}>
                {s.v}{s.u && <span style={{ fontSize: 9, color: "var(--ink-3)", marginLeft: 1 }}>{s.u}</span>}
              </span>
            </div>
          ))}
        </div>

        <div style={{
          marginTop: 10, paddingTop: 9, borderTop: "1px solid var(--rule)",
          display: "flex", justifyContent: "space-between", alignItems: "center",
        }}>
          <span style={{ ...jrStyles.italic, fontSize: 12, color: "var(--ink-3)" }}>{w.type}</span>
          <span style={{
            fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 600,
            letterSpacing: "0.12em", textTransform: "uppercase", color: "var(--coral)",
            display: "inline-flex", alignItems: "center", gap: 5,
          }}>
            Open in {w.source}
            <svg width="11" height="11" viewBox="0 0 11 11" style={{ display: "block" }}>
              <path d="M2.5 8.5 L8.5 2.5 M4 2.5 H8.5 V7" stroke="var(--coral)" strokeWidth="1.4"
                fill="none" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </span>
        </div>
      </div>
    </div>
  );
}

/* ─── small actions row (Edit / Done) ────────────────────────────── */

function ActionsRow() {
  return (
    <div style={{
      padding: "8px 24px 0 24px",
      display: "flex", justifyContent: "space-between", alignItems: "baseline",
    }}>
      <span style={{ ...jrStyles.eyebrow, color: "var(--coral)", cursor: "pointer" }}>EDIT</span>
      <span style={jrStyles.eyebrow}>DONE</span>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   DIRECTION A · "THE PAGE"
   A written page. The entry leads. Linked run sits right under the
   headline as a real card. AI + coach read as quiet supporting voices.
   ════════════════════════════════════════════════════════════════════ */

function JournalThePage() {
  const e = JR_ENTRY;
  return (
    <div style={{ height: "100%", background: "var(--paper)", display: "flex", flexDirection: "column", overflow: "hidden" }}>
      {/* Plate strip */}
      <div style={{ display: "flex", justifyContent: "space-between", padding: "14px 24px 0 24px" }}>
        <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
          <span style={{ ...jrStyles.eyebrow, color: "var(--ink)" }}>RUNNING LOG</span>
          <span style={jrStyles.eyebrow}>— JOURNAL · ENTRY</span>
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 2, textAlign: "right" }}>
          <span style={{ ...jrStyles.eyebrow, color: "var(--ink)" }}>{e.date.toUpperCase()}</span>
          <span style={jrStyles.eyebrow}>{e.time}</span>
        </div>
      </div>

      <ActionsRow />
      <Hairline style={{ margin: "10px 24px 0 24px", width: "auto" }} />

      <div style={{ flex: 1, overflowY: "auto", padding: "0 0 32px 0" }}>
        {/* Headline */}
        <div style={{ padding: "24px 24px 0 24px" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
            <h1 style={{
              fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 46,
              color: "var(--ink)", margin: 0, letterSpacing: "-0.01em", lineHeight: 0.95,
            }}>{e.day}</h1>
            <div style={{ marginTop: 6 }}><MoodPill mood={e.mood} /></div>
          </div>
          <p style={{ ...jrStyles.italic, fontSize: 14, color: "var(--ink-3)", margin: "12px 0 0 0" }}>
            — {e.dateline} —
          </p>
        </div>

        {/* Linked workout — promoted, right under the headline */}
        <div style={{ margin: "20px 24px 0 24px" }}>
          <LinkedWorkoutCard variant="plate" />
        </div>

        {/* THE ENTRY — the heart of the journal, on ruled paper */}
        <div style={{ padding: "26px 24px 0 24px" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
            <Eyebrow>YOUR ENTRY</Eyebrow>
            <span style={{ ...jrStyles.eyebrowSm, color: "var(--coral)", cursor: "pointer" }}>EDIT ✎</span>
          </div>
          <div style={{
            marginTop: 12,
            backgroundImage: "repeating-linear-gradient(to bottom, transparent 0, transparent 31px, var(--rule) 31px, var(--rule) 32px)",
            backgroundPosition: "0 6px",
          }}>
            <p style={{
              fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 17,
              lineHeight: "32px", color: "var(--ink)", margin: 0,
            }}>{e.note}</p>
          </div>
        </div>

        {/* THE READ — AI summary, quiet supporting voice */}
        <div style={{ margin: "28px 24px 0 24px", paddingTop: 16, borderTop: "1px solid var(--rule)" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
            <Eyebrow>THE READ</Eyebrow>
            <span style={{ ...jrStyles.eyebrowSm }}>AUTO</span>
          </div>
          <p style={{
            fontFamily: "var(--font-body)", fontSize: 14, lineHeight: 1.6,
            color: "var(--ink-2)", margin: "8px 0 0 0",
          }}>{e.aiSummary}</p>
        </div>

        {/* COACH */}
        <div style={{ margin: "22px 24px 0 24px", paddingTop: 16, borderTop: "1px solid var(--rule)" }}>
          <Eyebrow>FROM YOUR COACH</Eyebrow>
          <p style={{ ...jrStyles.italic, color: "var(--ink)", fontSize: 14, margin: "8px 0 0 0" }}>
            "{e.coach}"
          </p>
          <a style={{
            display: "inline-block", marginTop: 10,
            fontFamily: "var(--font-display)", fontWeight: 600, fontSize: 14,
            color: "var(--coral)", borderBottom: "1px solid var(--coral)",
            paddingBottom: 2, cursor: "pointer", textDecoration: "none",
          }}>Ask a follow-up →</a>
        </div>

        {/* Footer */}
        <div style={{
          margin: "30px 24px 0 24px", paddingTop: 14, borderTop: "1px solid var(--rule)",
          display: "flex", justifyContent: "space-between", alignItems: "baseline",
        }}>
          <span style={{ ...jrStyles.italic, fontSize: 12, color: "var(--ink-3)" }}>
            — Logged {e.date}, {e.time}. —
          </span>
          <span style={{ ...jrStyles.eyebrowSm, color: "var(--ink-3)", cursor: "pointer" }}>DELETE LOG</span>
        </div>
      </div>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   DIRECTION B · "FIELD NOTES"
   Treats the screen like a notebook page: coral margin rule down the
   left, date in the margin, the run clipped in like a pasted receipt.
   ════════════════════════════════════════════════════════════════════ */

function JournalFieldNotes() {
  const e = JR_ENTRY;
  const [note, setNote] = useState(e.note);

  return (
    <div style={{ height: "100%", background: "var(--paper)", display: "flex", flexDirection: "column", overflow: "hidden" }}>
      {/* Plate strip */}
      <div style={{ display: "flex", justifyContent: "space-between", padding: "14px 24px 0 24px" }}>
        <span style={{ ...jrStyles.eyebrow, color: "var(--ink)" }}>RUNNING LOG</span>
        <span style={jrStyles.eyebrow}>NOTEBOOK · {e.date.toUpperCase()}</span>
      </div>
      <ActionsRow />

      <div style={{ flex: 1, overflowY: "auto", padding: "0 0 32px 0", position: "relative" }}>
        {/* notebook margin rule */}
        <div style={{
          position: "absolute", top: 0, bottom: 0, left: 56,
          width: 1, background: "var(--coral-wash)",
        }} />

        {/* Header block — date sits in the margin */}
        <div style={{ display: "flex", marginTop: 18 }}>
          <div style={{ width: 56, flexShrink: 0, paddingTop: 8, textAlign: "center" }}>
            <div style={{ ...jrStyles.mono, fontSize: 11, fontWeight: 600, color: "var(--coral)" }}>16</div>
            <div style={{ ...jrStyles.eyebrowSm, fontSize: 8, marginTop: 2 }}>JUN</div>
          </div>
          <div style={{ flex: 1, paddingRight: 24, paddingLeft: 16 }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
              <h1 style={{
                fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 34,
                color: "var(--ink)", margin: 0, letterSpacing: "-0.01em", lineHeight: 1,
              }}>{e.day}</h1>
              <div style={{ marginTop: 2 }}><MoodPill mood={e.mood} /></div>
            </div>
            <p style={{ ...jrStyles.italic, fontSize: 13, color: "var(--ink-3)", margin: "8px 0 0 0" }}>
              — {e.dateline} —
            </p>
          </div>
        </div>

        {/* THE NOTE — editable, handwritten feel */}
        <div style={{ display: "flex", marginTop: 22 }}>
          <div style={{ width: 56, flexShrink: 0, textAlign: "center", paddingTop: 2 }}>
            <span style={{ ...jrStyles.eyebrowSm, fontSize: 8 }}>NOTE</span>
          </div>
          <div style={{ flex: 1, paddingRight: 24, paddingLeft: 16 }}>
            <textarea
              value={note}
              onChange={(ev) => setNote(ev.target.value)}
              style={{
                width: "100%", minHeight: 150, resize: "none", border: 0, outline: "none",
                background: "transparent", padding: 0, boxSizing: "border-box",
                fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 16,
                lineHeight: "30px", color: "var(--ink)",
                backgroundImage: "repeating-linear-gradient(to bottom, transparent 0, transparent 29px, var(--rule) 29px, var(--rule) 30px)",
                backgroundPosition: "0 5px",
              }}
            />
          </div>
        </div>

        {/* Linked run — clipped in like a pasted receipt */}
        <div style={{ display: "flex", marginTop: 14 }}>
          <div style={{ width: 56, flexShrink: 0, textAlign: "center", paddingTop: 16 }}>
            <span style={{ ...jrStyles.eyebrowSm, fontSize: 8 }}>RUN</span>
          </div>
          <div style={{ flex: 1, paddingRight: 24, paddingLeft: 16 }}>
            <LinkedWorkoutCard variant="ledger" />
          </div>
        </div>

        {/* The read + coach — in the margin layout */}
        <div style={{ display: "flex", marginTop: 24 }}>
          <div style={{ width: 56, flexShrink: 0, textAlign: "center", paddingTop: 2 }}>
            <span style={{ ...jrStyles.eyebrowSm, fontSize: 8 }}>READ</span>
          </div>
          <div style={{ flex: 1, paddingRight: 24, paddingLeft: 16 }}>
            <p style={{
              fontFamily: "var(--font-body)", fontSize: 14, lineHeight: 1.6,
              color: "var(--ink-2)", margin: 0,
            }}>{e.aiSummary}</p>
            <p style={{ ...jrStyles.italic, color: "var(--ink)", fontSize: 14, margin: "14px 0 0 0" }}>
              "{e.coach}"
            </p>
            <a style={{
              display: "inline-block", marginTop: 10,
              fontFamily: "var(--font-display)", fontWeight: 600, fontSize: 14,
              color: "var(--coral)", borderBottom: "1px solid var(--coral)",
              paddingBottom: 2, cursor: "pointer", textDecoration: "none",
            }}>Ask your coach →</a>
          </div>
        </div>

        {/* Footer */}
        <div style={{ display: "flex", marginTop: 28 }}>
          <div style={{ width: 56, flexShrink: 0 }} />
          <div style={{
            flex: 1, paddingRight: 24, paddingLeft: 16, paddingTop: 14,
            borderTop: "1px solid var(--rule)",
            display: "flex", justifyContent: "space-between", alignItems: "baseline",
          }}>
            <span style={{ ...jrStyles.italic, fontSize: 12, color: "var(--ink-3)" }}>
              — Logged {e.date}, {e.time}. —
            </span>
            <span style={{ ...jrStyles.eyebrowSm, color: "var(--ink-3)", cursor: "pointer" }}>DELETE</span>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ── export to window for the canvas ─────────────────────────────── */
Object.assign(window, {
  JournalThePage,
  JournalFieldNotes,
  LinkedWorkoutCard,
});

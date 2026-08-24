/* global React, Eyebrow, Hairline, MoodPill */
/* ════════════════════════════════════════════════════════════════════
   JOURNAL ENTRY · LIGHT POLISH
   Same bones as the production entry-detail — it just read a little
   flat. Minimal moves to give it life, nothing added that crowds:
     • a one-line dateline under the day for voice/warmth
     • the lonely single "DIST" becomes a quiet 3-stat strip (rhythm)
     • the faint "LINKED · STRAVA" hairline gets a small route mark + a
       clearer in-app "View workout detail →"
     • a touch more type hierarchy; coral used only where it acts
   Order, sections and content otherwise unchanged.
   ════════════════════════════════════════════════════════════════════ */

const jpStyles = {
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

const JP = {
  day: "Tuesday",
  date: "JUN 16",
  time: "6:09 PM",
  mood: "positive",
  dateline: "a humid evening seven, taken easy on purpose.",
  stats: [
    { l: "DIST", v: "7.0", u: "mi" },
    { l: "TIME", v: "53:48" },
    { l: "PACE", v: "7:41", u: "/mi" },
  ],
  aiSummary:
    "I completed a 7-mile moderate run today. I felt pretty comfortable and " +
    "achieved a good steady effort, setting myself up for tomorrow's workout. " +
    "The humidity was noticeable but manageable.",
  coach:
    "It's great that your moderate 7-mile run felt comfortable, especially " +
    "after recently feeling fatigued. This prepares you well for tomorrow's " +
    "workout, so focus on optimal recovery and fuelling tonight to maximise " +
    "your performance.",
  notes: "Distance: 7 miles\nWorkout Type: Moderate run",
};

function JournalRevised() {
  const e = JP;
  return (
    <div style={{ height: "100%", background: "var(--paper)", display: "flex", flexDirection: "column", overflow: "hidden" }}>
      {/* plate strip */}
      <div style={{ display: "flex", justifyContent: "space-between", padding: "14px 24px 0 24px" }}>
        <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
          <span style={{ ...jpStyles.eyebrow, color: "var(--ink)" }}>RUNNING LOG</span>
          <span style={jpStyles.eyebrow}>— JOURNAL · ENTRY DETAIL</span>
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 2, textAlign: "right" }}>
          <span style={{ ...jpStyles.eyebrow, color: "var(--ink)" }}>{e.date}</span>
          <span style={jpStyles.eyebrow}>{e.time}</span>
        </div>
      </div>

      {/* actions */}
      <div style={{ padding: "10px 24px 0 24px", display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
        <span style={{ ...jpStyles.eyebrow, color: "var(--coral)", cursor: "pointer" }}>EDIT</span>
        <span style={jpStyles.eyebrow}>DONE</span>
      </div>
      <Hairline style={{ margin: "12px 24px 0 24px", width: "auto" }} />

      <div style={{ flex: 1, overflowY: "auto", padding: "0 0 32px 0" }}>
        {/* headline + mood + dateline */}
        <div style={{ padding: "26px 24px 0 24px" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
            <h1 style={{
              fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 48,
              color: "var(--ink)", margin: 0, letterSpacing: "-0.015em", lineHeight: 0.92,
            }}>{e.day}</h1>
            <div style={{ marginTop: 8 }}><MoodPill mood={e.mood} /></div>
          </div>
          <p style={{ ...jpStyles.italic, fontSize: 14, color: "var(--ink-3)", margin: "12px 0 0 0" }}>
            — {e.dateline} —
          </p>
        </div>

        {/* stat strip — replaces the single lonely DIST */}
        <div style={{
          margin: "22px 24px 0 24px",
          display: "grid", gridTemplateColumns: "repeat(3, 1fr)",
          borderTop: "1px solid var(--rule)", borderBottom: "1px solid var(--rule)",
        }}>
          {e.stats.map((s, i, arr) => (
            <div key={s.l} style={{
              padding: "14px 8px",
              borderRight: i < arr.length - 1 ? "1px solid var(--rule)" : "none",
              display: "flex", flexDirection: "column", alignItems: "center", gap: 7,
            }}>
              <span style={jpStyles.eyebrowSm}>{s.l}</span>
              <span style={{ ...jpStyles.mono, fontSize: 24, fontWeight: 600, color: "var(--ink)", lineHeight: 1 }}>
                {s.v}{s.u && <span style={{ fontSize: 11, color: "var(--ink-3)", marginLeft: 2 }}>{s.u}</span>}
              </span>
            </div>
          ))}
        </div>

        {/* linked workout — a touch more present, opens in-app */}
        <div style={{
          margin: "16px 24px 0 24px",
          display: "flex", alignItems: "center", gap: 12,
          padding: "12px 14px",
          background: "var(--paper-elevated)", border: "1px solid var(--rule)",
          cursor: "pointer",
        }}>
          <div style={{
            width: 40, height: 40, flexShrink: 0, background: "var(--paper-deep)",
            border: "1px solid var(--rule)", overflow: "hidden",
          }}>
            <svg viewBox="0 0 40 40" style={{ width: "100%", height: "100%", display: "block" }}>
              <path d="M 8 31 Q 12 17, 20 20 T 30 11 Q 33 9, 32 16"
                fill="none" stroke="var(--coral)" strokeWidth="1.8"
                strokeLinecap="round" strokeLinejoin="round" />
              <circle cx="8" cy="31" r="2.4" fill="var(--ink)" />
              <circle cx="32" cy="16" r="2.4" fill="var(--coral)" />
            </svg>
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <span style={jpStyles.eyebrowSm}>LINKED RUN · SYNCED · STRAVA</span>
            <div style={{ ...jpStyles.italic, fontSize: 13, color: "var(--ink-2)", marginTop: 3 }}>Moderate run · 5:14 PM</div>
          </div>
          <span style={{
            fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 600,
            letterSpacing: "0.10em", textTransform: "uppercase", color: "var(--coral)",
            display: "inline-flex", alignItems: "center", gap: 5, flexShrink: 0,
          }}>
            Detail
            <svg width="11" height="11" viewBox="0 0 11 11" style={{ display: "block" }}>
              <path d="M2.5 5.5 H8 M5.5 3 L8 5.5 L5.5 8" stroke="var(--coral)" strokeWidth="1.4"
                fill="none" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </span>
        </div>

        {/* voice recap (AI summary of the voice memo) */}
        <div style={{ padding: "26px 24px 0 24px" }}>
          <Eyebrow>VOICE RECAP</Eyebrow>
          <p style={{
            fontFamily: "var(--font-body)", fontSize: 16, lineHeight: 1.6,
            color: "var(--ink)", margin: "10px 0 0 0",
          }}>{e.aiSummary}</p>
        </div>

        {/* workout notes */}
        <div style={{ margin: "24px 24px 0 24px", paddingTop: 18, borderTop: "1px solid var(--rule)" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
            <Eyebrow>WORKOUT NOTES</Eyebrow>
            <span style={jpStyles.eyebrowSm}>OPTIONAL</span>
          </div>
          <p style={{
            fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 15,
            lineHeight: 1.7, color: "var(--ink)", margin: "10px 0 0 0", whiteSpace: "pre-line",
          }}>{e.notes}</p>
          <div style={{ display: "flex", justifyContent: "flex-end", marginTop: 8 }}>
            <span style={{ ...jpStyles.eyebrow, color: "var(--coral)", cursor: "pointer" }}>SAVE</span>
          </div>
        </div>

        {/* coach insight */}
        <div style={{ margin: "24px 24px 0 24px", paddingTop: 18, borderTop: "1px solid var(--rule)" }}>
          <Eyebrow>COACH INSIGHT</Eyebrow>
          <p style={{ ...jpStyles.italic, color: "var(--ink)", fontSize: 15, margin: "10px 0 0 0", lineHeight: 1.6 }}>
            {e.coach}
          </p>
          <div style={{ display: "flex", justifyContent: "flex-end", marginTop: 14 }}>
            <button style={{
              fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 600,
              letterSpacing: "0.12em", textTransform: "uppercase", color: "var(--coral)",
              background: "var(--paper-elevated)", border: "1px solid var(--coral)",
              padding: "9px 14px", cursor: "pointer",
              display: "inline-flex", alignItems: "center", gap: 7,
            }}>
              Generate AI Insight
              <svg width="11" height="11" viewBox="0 0 11 11" style={{ display: "block" }}>
                <path d="M2.5 5.5 H8 M5.5 3 L8 5.5 L5.5 8" stroke="var(--coral)" strokeWidth="1.4"
                  fill="none" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </button>
          </div>
        </div>

        {/* footer */}
        <div style={{
          margin: "26px 24px 0 24px", paddingTop: 14, borderTop: "1px solid var(--rule)",
          display: "flex", justifyContent: "space-between", alignItems: "baseline",
        }}>
          <span style={{ ...jpStyles.italic, fontSize: 12, color: "var(--ink-3)" }}>
            — Logged Jun 16, {e.time}. —
          </span>
          <span style={{ ...jpStyles.eyebrowSm, color: "var(--ink-3)", cursor: "pointer" }}>DELETE LOG</span>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { JournalRevised });

/* global React, Eyebrow, Hairline, MoodPill */
/* ════════════════════════════════════════════════════════════════════
   JOURNAL ENTRY · REDESIGN v2  — RE-DIRECTED
   A real journal entry, assembled from the things you actually capture
   after a run:
     • MOOD            — how it felt
     • WORKOUT TYPE    — what it was
     • VOICE MEMO      — what you said into the phone, with transcript
     • YOUR NOTES      — what you wrote
     • WORKOUT NOTES   — auto-populated facts from the synced run
     • AI INSIGHT      — the read + coach
   The linked run opens the IN-APP workout detail (not Strava).
   Voice / vocabulary: warm paper, ink, one coral, hairlines + plates.
   ════════════════════════════════════════════════════════════════════ */

const { useState } = React;

/* ─── the Tuesday entry fixture ──────────────────────────────────── */

const J2 = {
  day: "Tuesday",
  date: "Jun 16",
  time: "6:09 PM",
  mood: "positive",
  type: "Moderate run",
  dateline: "a humid evening seven, taken easy on purpose.",

  voice: {
    duration: "0:42",
    transcript:
      "Legs were dead the first couple miles — humidity was brutal. " +
      "Settled in around three and the last few actually felt smooth. " +
      "Glad I held back, saving it for Thursday.",
  },

  notes:
    "Shoes: Endorphin Speed, second run in them — felt springy. Need to " +
    "start hydrating earlier on days like this.",

  // auto-populated from the synced workout
  workoutNotes: [
    { k: "Distance", v: "7.0 mi" },
    { k: "Type", v: "Moderate run" },
    { k: "Time", v: "53:48" },
    { k: "Avg pace", v: "7:41 /mi" },
    { k: "Avg HR", v: "146 bpm" },
    { k: "Conditions", v: "78°F · humid" },
  ],

  aiSummary:
    "A 7-mile moderate run at a comfortable, steady effort. Humidity was " +
    "noticeable but manageable — a solid aerobic day that sets up tomorrow.",
  coach:
    "Great that the moderate seven felt comfortable, especially coming off a " +
    "fatigued stretch. Prioritise recovery and fuelling tonight to get the " +
    "most out of Thursday.",
};

/* run summary for the linked card */
const J2_RUN = {
  type: "Moderate run",
  distMi: "7.0",
  time: "53:48",
  pace: "7:41",
  hr: "146",
  synced: "Strava",
  at: "5:14 PM",
};

/* ─── shared inline tokens ───────────────────────────────────────── */

const j2Styles = {
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

/* deterministic waveform heights (0..1) */
const WAVE = [
  0.30, 0.55, 0.40, 0.70, 0.85, 0.60, 0.45, 0.75, 0.95, 0.65,
  0.50, 0.35, 0.55, 0.80, 1.00, 0.70, 0.45, 0.60, 0.40, 0.30,
  0.50, 0.72, 0.88, 0.62, 0.42, 0.58, 0.78, 0.92, 0.55, 0.38,
  0.48, 0.66, 0.84, 0.58, 0.40, 0.52, 0.70, 0.46, 0.34, 0.28,
];

/* ─── reusable section header ────────────────────────────────────── */

function SecHead({ label, right }) {
  return (
    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
      <Eyebrow>{label}</Eyebrow>
      {right && <span style={j2Styles.eyebrowSm}>{right}</span>}
    </div>
  );
}

/* ─── workout type chip ──────────────────────────────────────────── */

function TypeChip({ children }) {
  return (
    <span style={{
      display: "inline-flex", alignItems: "center", gap: 6,
      padding: "5px 10px",
      border: "1px solid var(--rule)", background: "var(--paper-elevated)",
      fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 600,
      letterSpacing: "0.12em", textTransform: "uppercase", color: "var(--ink-2)",
    }}>
      <span style={{ width: 5, height: 5, borderRadius: 999, background: "var(--coral)" }} />
      {children}
    </span>
  );
}

/* ─── voice memo block ───────────────────────────────────────────── */

function VoiceMemo({ showTranscript = true }) {
  const [playing, setPlaying] = useState(false);
  const [open, setOpen] = useState(showTranscript);
  const v = J2.voice;
  const progress = playing ? 0.38 : 0; // played fraction

  return (
    <div>
      <div style={{
        display: "flex", alignItems: "center", gap: 14,
        padding: "12px 14px",
        background: "var(--paper-elevated)", border: "1px solid var(--rule)",
      }}>
        {/* play button */}
        <button
          onClick={() => setPlaying(p => !p)}
          style={{
            width: 40, height: 40, borderRadius: 999, flexShrink: 0,
            border: "none", cursor: "pointer", background: "var(--coral)",
            display: "flex", alignItems: "center", justifyContent: "center",
            boxShadow: "var(--shadow-coral)",
          }}
        >
          {playing ? (
            <svg width="12" height="13" viewBox="0 0 12 13"><rect x="1" y="1" width="3.5" height="11" rx="1" fill="#fff"/><rect x="7.5" y="1" width="3.5" height="11" rx="1" fill="#fff"/></svg>
          ) : (
            <svg width="13" height="14" viewBox="0 0 13 14" style={{ marginLeft: 2 }}><path d="M1 1.5 L12 7 L1 12.5 Z" fill="#fff"/></svg>
          )}
        </button>

        {/* waveform */}
        <div style={{ flex: 1, display: "flex", alignItems: "center", gap: 2, height: 34, minWidth: 0 }}>
          {WAVE.map((h, i) => (
            <div key={i} style={{
              flex: 1, height: `${Math.max(10, h * 100)}%`, borderRadius: 1,
              background: (i / WAVE.length) < progress ? "var(--coral)" : "var(--ink-3)",
              opacity: (i / WAVE.length) < progress ? 1 : 0.45,
            }} />
          ))}
        </div>

        <span style={{ ...j2Styles.mono, fontSize: 12, fontWeight: 600, color: "var(--ink-2)", flexShrink: 0 }}>
          {v.duration}
        </span>
      </div>

      {/* transcript */}
      {open && (
        <p style={{
          ...j2Styles.italic, color: "var(--ink)", fontSize: 14,
          margin: "12px 0 0 0",
        }}>
          "{v.transcript}"
        </p>
      )}
      <button
        onClick={() => setOpen(o => !o)}
        style={{
          marginTop: 8, padding: 0, border: "none", background: "none", cursor: "pointer",
          ...j2Styles.eyebrowSm, color: "var(--ink-3)",
        }}
      >
        {open ? "HIDE TRANSCRIPT" : "SHOW TRANSCRIPT"}
      </button>
    </div>
  );
}

/* ─── linked workout card — opens IN-APP detail ──────────────────── */

function LinkedRunCard() {
  const r = J2_RUN;
  const stats = [
    { l: "DIST", v: r.distMi, u: "mi" },
    { l: "TIME", v: r.time },
    { l: "PACE", v: r.pace, u: "/mi" },
    { l: "HR", v: r.hr },
  ];
  return (
    <div style={{
      display: "flex", alignItems: "stretch", gap: 14, padding: "14px",
      background: "var(--paper-elevated)", border: "1px solid var(--rule)",
      cursor: "pointer",
    }}>
      {/* mini route */}
      <div style={{
        width: 60, height: 60, flexShrink: 0, background: "var(--paper-deep)",
        border: "1px solid var(--rule)", overflow: "hidden",
      }}>
        <svg viewBox="0 0 60 60" style={{ width: "100%", height: "100%", display: "block" }}>
          <path d="M 11 47 Q 17 26, 30 30 T 45 17 Q 50 13, 48 24"
            fill="none" stroke="var(--coral)" strokeWidth="2"
            strokeLinecap="round" strokeLinejoin="round" />
          <circle cx="11" cy="47" r="3" fill="var(--ink)" />
          <circle cx="48" cy="24" r="3" fill="var(--coral)" />
        </svg>
      </div>

      <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "space-between", minWidth: 0 }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
          <span style={j2Styles.eyebrowSm}>LINKED RUN</span>
          <span style={j2Styles.eyebrowSm}>SYNCED · {r.synced.toUpperCase()}</span>
        </div>

        <div style={{ display: "flex", gap: 16, marginTop: 8 }}>
          {stats.map(s => (
            <div key={s.l} style={{ display: "flex", flexDirection: "column", gap: 3 }}>
              <span style={{ ...j2Styles.eyebrowSm, fontSize: 8 }}>{s.l}</span>
              <span style={{ ...j2Styles.mono, fontSize: 15, fontWeight: 600, color: "var(--ink)", lineHeight: 1 }}>
                {s.v}{s.u && <span style={{ fontSize: 9, color: "var(--ink-3)", marginLeft: 1 }}>{s.u}</span>}
              </span>
            </div>
          ))}
        </div>

        <div style={{
          marginTop: 10, paddingTop: 9, borderTop: "1px solid var(--rule)",
          display: "flex", justifyContent: "space-between", alignItems: "center",
        }}>
          <span style={{ ...j2Styles.italic, fontSize: 12, color: "var(--ink-3)" }}>{r.type}</span>
          <span style={{
            fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 600,
            letterSpacing: "0.12em", textTransform: "uppercase", color: "var(--coral)",
            display: "inline-flex", alignItems: "center", gap: 5,
          }}>
            View workout detail
            <svg width="11" height="11" viewBox="0 0 11 11" style={{ display: "block" }}>
              <path d="M2.5 5.5 H8 M5.5 3 L8 5.5 L5.5 8" stroke="var(--coral)" strokeWidth="1.4"
                fill="none" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </span>
        </div>
      </div>
    </div>
  );
}

/* ─── auto-populated workout notes ───────────────────────────────── */

function WorkoutNotesAuto() {
  return (
    <div style={{ marginTop: 10, borderTop: "1px solid var(--rule)" }}>
      {J2.workoutNotes.map((row, i) => (
        <div key={row.k} style={{
          display: "flex", justifyContent: "space-between", alignItems: "baseline",
          padding: "9px 0",
          borderBottom: i < J2.workoutNotes.length - 1 ? "1px solid var(--rule)" : "none",
        }}>
          <span style={{ ...j2Styles.eyebrowSm, color: "var(--ink-2)" }}>{row.k.toUpperCase()}</span>
          <span style={{ ...j2Styles.mono, fontSize: 13, fontWeight: 600, color: "var(--ink)" }}>{row.v}</span>
        </div>
      ))}
    </div>
  );
}

/* ─── actions row ────────────────────────────────────────────────── */

function Actions() {
  return (
    <div style={{ padding: "8px 24px 0 24px", display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
      <span style={{ ...j2Styles.eyebrow, color: "var(--coral)", cursor: "pointer" }}>EDIT</span>
      <span style={j2Styles.eyebrow}>DONE</span>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   DIRECTION A · "THE PAGE"
   One scrolling column. Mood + type in the header, your voice & words
   first, the run one tap away, auto facts, then the read.
   ════════════════════════════════════════════════════════════════════ */

function JournalEntryPage() {
  const e = J2;
  return (
    <div style={{ height: "100%", background: "var(--paper)", display: "flex", flexDirection: "column", overflow: "hidden" }}>
      {/* plate */}
      <div style={{ display: "flex", justifyContent: "space-between", padding: "14px 24px 0 24px" }}>
        <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
          <span style={{ ...j2Styles.eyebrow, color: "var(--ink)" }}>RUNNING LOG</span>
          <span style={j2Styles.eyebrow}>— JOURNAL · ENTRY</span>
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 2, textAlign: "right" }}>
          <span style={{ ...j2Styles.eyebrow, color: "var(--ink)" }}>{e.date.toUpperCase()}</span>
          <span style={j2Styles.eyebrow}>{e.time}</span>
        </div>
      </div>
      <Actions />
      <Hairline style={{ margin: "10px 24px 0 24px", width: "auto" }} />

      <div style={{ flex: 1, overflowY: "auto", padding: "0 0 32px 0" }}>
        {/* headline — day + mood + type */}
        <div style={{ padding: "24px 24px 0 24px" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
            <h1 style={{
              fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 46,
              color: "var(--ink)", margin: 0, letterSpacing: "-0.01em", lineHeight: 0.95,
            }}>{e.day}</h1>
            <div style={{ marginTop: 6 }}><MoodPill mood={e.mood} /></div>
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: 10, marginTop: 14, flexWrap: "wrap" }}>
            <TypeChip>{e.type}</TypeChip>
            <span style={{ ...j2Styles.italic, fontSize: 13, color: "var(--ink-3)" }}>— {e.dateline}</span>
          </div>
        </div>

        {/* voice memo */}
        <div style={{ padding: "24px 24px 0 24px" }}>
          <SecHead label="VOICE MEMO" right="JUST AFTER" />
          <div style={{ marginTop: 12 }}><VoiceMemo /></div>
        </div>

        {/* your notes */}
        <div style={{ padding: "24px 24px 0 24px" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
            <Eyebrow>YOUR NOTES</Eyebrow>
            <span style={{ ...j2Styles.eyebrowSm, color: "var(--coral)", cursor: "pointer" }}>EDIT ✎</span>
          </div>
          <p style={{
            fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 16,
            lineHeight: "29px", color: "var(--ink)", margin: "12px 0 0 0",
            backgroundImage: "repeating-linear-gradient(to bottom, transparent 0, transparent 28px, var(--rule) 28px, var(--rule) 29px)",
          }}>{e.notes}</p>
        </div>

        {/* linked run — in-app */}
        <div style={{ padding: "24px 24px 0 24px" }}>
          <SecHead label="THE RUN" />
          <div style={{ marginTop: 12 }}><LinkedRunCard /></div>
        </div>

        {/* auto workout notes */}
        <div style={{ padding: "24px 24px 0 24px" }}>
          <SecHead label="WORKOUT NOTES" right="AUTO" />
          <WorkoutNotesAuto />
        </div>

        {/* AI insight */}
        <div style={{ margin: "26px 24px 0 24px", paddingTop: 16, borderTop: "1px solid var(--rule)" }}>
          <SecHead label="AI INSIGHT" right="THE READ" />
          <p style={{
            fontFamily: "var(--font-body)", fontSize: 14, lineHeight: 1.6,
            color: "var(--ink-2)", margin: "8px 0 0 0",
          }}>{e.aiSummary}</p>
          <p style={{ ...j2Styles.italic, color: "var(--ink)", fontSize: 14, margin: "14px 0 0 0" }}>
            "{e.coach}"
          </p>
          <a style={{
            display: "inline-block", marginTop: 10,
            fontFamily: "var(--font-display)", fontWeight: 600, fontSize: 14,
            color: "var(--coral)", borderBottom: "1px solid var(--coral)",
            paddingBottom: 2, cursor: "pointer", textDecoration: "none",
          }}>Ask a follow-up →</a>
        </div>

        {/* footer */}
        <div style={{
          margin: "28px 24px 0 24px", paddingTop: 14, borderTop: "1px solid var(--rule)",
          display: "flex", justifyContent: "space-between", alignItems: "baseline",
        }}>
          <span style={{ ...j2Styles.italic, fontSize: 12, color: "var(--ink-3)" }}>— Logged {e.date}, {e.time}. —</span>
          <span style={{ ...j2Styles.eyebrowSm, color: "var(--ink-3)", cursor: "pointer" }}>DELETE LOG</span>
        </div>
      </div>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   DIRECTION B · "FIELD NOTES"
   Notebook margin down the left; each block is labelled in the gutter.
   Same ingredients, more overtly a journal page.
   ════════════════════════════════════════════════════════════════════ */

function GutterRow({ tag, children, top = 2 }) {
  return (
    <div style={{ display: "flex", marginTop: 22 }}>
      <div style={{ width: 56, flexShrink: 0, textAlign: "center", paddingTop: top }}>
        <span style={{ ...j2Styles.eyebrowSm, fontSize: 8 }}>{tag}</span>
      </div>
      <div style={{ flex: 1, paddingRight: 24, paddingLeft: 16, minWidth: 0 }}>{children}</div>
    </div>
  );
}

function JournalEntryFieldNotes() {
  const e = J2;
  return (
    <div style={{ height: "100%", background: "var(--paper)", display: "flex", flexDirection: "column", overflow: "hidden" }}>
      <div style={{ display: "flex", justifyContent: "space-between", padding: "14px 24px 0 24px" }}>
        <span style={{ ...j2Styles.eyebrow, color: "var(--ink)" }}>RUNNING LOG</span>
        <span style={j2Styles.eyebrow}>NOTEBOOK · {e.date.toUpperCase()}</span>
      </div>
      <Actions />

      <div style={{ flex: 1, overflowY: "auto", padding: "0 0 32px 0", position: "relative" }}>
        {/* margin rule */}
        <div style={{ position: "absolute", top: 0, bottom: 0, left: 56, width: 1, background: "var(--coral-wash)" }} />

        {/* header */}
        <div style={{ display: "flex", marginTop: 18 }}>
          <div style={{ width: 56, flexShrink: 0, paddingTop: 6, textAlign: "center" }}>
            <div style={{ ...j2Styles.mono, fontSize: 11, fontWeight: 600, color: "var(--coral)" }}>16</div>
            <div style={{ ...j2Styles.eyebrowSm, fontSize: 8, marginTop: 2 }}>JUN</div>
          </div>
          <div style={{ flex: 1, paddingRight: 24, paddingLeft: 16 }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
              <h1 style={{
                fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 34,
                color: "var(--ink)", margin: 0, letterSpacing: "-0.01em", lineHeight: 1,
              }}>{e.day}</h1>
              <div style={{ marginTop: 2 }}><MoodPill mood={e.mood} /></div>
            </div>
            <div style={{ marginTop: 10 }}><TypeChip>{e.type}</TypeChip></div>
            <p style={{ ...j2Styles.italic, fontSize: 13, color: "var(--ink-3)", margin: "10px 0 0 0" }}>— {e.dateline}</p>
          </div>
        </div>

        <GutterRow tag="VOICE"><VoiceMemo /></GutterRow>

        <GutterRow tag="NOTE">
          <p style={{
            fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 15,
            lineHeight: "28px", color: "var(--ink)", margin: 0,
            backgroundImage: "repeating-linear-gradient(to bottom, transparent 0, transparent 27px, var(--rule) 27px, var(--rule) 28px)",
          }}>{e.notes}</p>
        </GutterRow>

        <GutterRow tag="RUN" top={16}><LinkedRunCard /></GutterRow>

        <GutterRow tag="STATS">
          <span style={{ ...j2Styles.eyebrowSm }}>WORKOUT NOTES · AUTO</span>
          <WorkoutNotesAuto />
        </GutterRow>

        <GutterRow tag="READ">
          <p style={{
            fontFamily: "var(--font-body)", fontSize: 14, lineHeight: 1.6,
            color: "var(--ink-2)", margin: 0,
          }}>{e.aiSummary}</p>
          <p style={{ ...j2Styles.italic, color: "var(--ink)", fontSize: 14, margin: "14px 0 0 0" }}>
            "{e.coach}"
          </p>
          <a style={{
            display: "inline-block", marginTop: 10,
            fontFamily: "var(--font-display)", fontWeight: 600, fontSize: 14,
            color: "var(--coral)", borderBottom: "1px solid var(--coral)",
            paddingBottom: 2, cursor: "pointer", textDecoration: "none",
          }}>Ask your coach →</a>
        </GutterRow>

        {/* footer */}
        <div style={{ display: "flex", marginTop: 26 }}>
          <div style={{ width: 56, flexShrink: 0 }} />
          <div style={{
            flex: 1, paddingRight: 24, paddingLeft: 16, paddingTop: 14,
            borderTop: "1px solid var(--rule)",
            display: "flex", justifyContent: "space-between", alignItems: "baseline",
          }}>
            <span style={{ ...j2Styles.italic, fontSize: 12, color: "var(--ink-3)" }}>— Logged {e.date}, {e.time}. —</span>
            <span style={{ ...j2Styles.eyebrowSm, color: "var(--ink-3)", cursor: "pointer" }}>DELETE</span>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ── export ──────────────────────────────────────────────────────── */
Object.assign(window, {
  JournalEntryPage,
  JournalEntryFieldNotes,
});

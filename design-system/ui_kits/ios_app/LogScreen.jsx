// Post Run Drip · iOS UI kit · Log screen (Voice Log)
//
// Mirrors RunningLog/Workouts/VoiceLogView.swift — hero section with
// the pulsing coral record button as the one loud accent, then a
// "type notes" hairline-bound section, then a journal feed of
// recent entries (JournalLogRow-style).
//
// The record button is THE place the design system's restraint
// deliberately breaks: 88px coral disc + breathing ring +
// shadow-coral. Everything else stays ink-on-paper.

const RECORD_PULSE_CSS = `
@keyframes prd-record-pulse {
  0%, 100% { transform: scale(1.0); opacity: 0.55; }
  50%      { transform: scale(1.12); opacity: 0.15; }
}
@keyframes prd-record-press {
  0%, 100% { transform: scale(1.03); }
  50%      { transform: scale(1.00); }
}
.prd-record {
  position: relative;
  width: 120px; height: 120px;
  display: grid; place-items: center;
  cursor: pointer;
  user-select: none;
  -webkit-tap-highlight-color: transparent;
}
.prd-record__ring {
  position: absolute; inset: 0;
  border-radius: 999px;
  border: 1.5px solid rgba(212, 89, 42, 0.20);
  animation: prd-record-pulse 1800ms ease-in-out infinite;
  opacity: 0; transition: opacity .25s ease-out;
}
.prd-record.is-recording .prd-record__ring { opacity: 1; }
.prd-record__disc {
  width: 88px; height: 88px;
  border-radius: 999px;
  background: var(--coral);
  box-shadow: 0 4px 12px rgba(212, 89, 42, 0.30);
  display: grid; place-items: center;
  transition: transform .25s ease-out, background .15s ease-out;
}
.prd-record:active .prd-record__disc { transform: scale(0.98); background: var(--coral-deep); }
.prd-record.is-recording .prd-record__disc { transform: scale(1.03); }
.prd-record__inner-circle {
  width: 32px; height: 32px; border-radius: 999px; background: #fff;
  transition: all .25s ease-out;
}
.prd-record.is-recording .prd-record__inner-circle {
  width: 24px; height: 24px; border-radius: 4px;
}

/* Mode toggle */
.prd-mode {
  display: grid; grid-template-columns: 1fr 1fr;
  border-top: 1px solid var(--rule);
  border-bottom: 1px solid var(--rule);
}
.prd-mode__btn {
  padding: 14px 0 0 0;
  text-align: center;
  cursor: pointer;
  background: transparent; border: 0;
  font-family: var(--font-mono);
  font-size: 11px; font-weight: 500;
  letter-spacing: 0.12em; text-transform: uppercase;
  color: var(--ink-2);
}
.prd-mode__btn.is-active { color: var(--coral); }
.prd-mode__rail {
  height: 2px; background: transparent; margin-top: 10px;
  transition: background .2s ease-out;
}
.prd-mode__btn.is-active .prd-mode__rail { background: var(--coral); }

/* Hairline-bound section (linked workout / type notes / journal) */
.prd-hl-section {
  border-bottom: 1px solid var(--rule);
  padding: 14px 24px;
}
.prd-hl-section--clickable { cursor: pointer; }
.prd-hl-section--clickable:hover { background: rgba(0,0,0,0.015); }

/* Journal row */
.prd-journal-row {
  display: grid;
  grid-template-columns: 2px 1fr;
  gap: 14px;
  padding: 22px 24px;
  border-bottom: 1px solid var(--rule);
  cursor: pointer;
}
.prd-journal-row__rail {
  border-radius: 1px;
  margin: 4px 0;
}
.prd-journal-row__day {
  font-family: var(--font-display);
  font-weight: 700;
  font-size: 20px;
  color: var(--ink);
  letter-spacing: -0.01em;
}
.prd-journal-row__meta {
  font-family: var(--font-mono);
  font-size: 10px; font-weight: 500;
  letter-spacing: 0.08em;
  color: var(--ink-2);
  margin-top: 4px;
  text-transform: uppercase;
}
.prd-journal-row__body {
  font-family: var(--font-body);
  font-style: italic;
  font-size: 14px;
  line-height: 1.55;
  color: var(--ink);
  margin-top: 14px;
  display: -webkit-box;
  -webkit-line-clamp: 3;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
.prd-journal-row__mood {
  font-family: var(--font-mono);
  font-size: 10px; font-weight: 500;
  letter-spacing: 0.10em;
  margin-top: 14px;
  text-transform: uppercase;
}
.prd-journal-row__indicator {
  display: inline-flex; align-items: center; gap: 5px;
  font-family: var(--font-mono);
  font-size: 10px; font-weight: 500;
  letter-spacing: 0.08em;
}
`;

// ---- The pulsing record button ------------------------------------------
const RecordButton = ({ isRecording, onClick }) => (
  <div
    className={"prd-record" + (isRecording ? " is-recording" : "")}
    onClick={onClick}
    role="button"
    aria-label={isRecording ? "Stop recording" : "Start voice memo"}
  >
    <div className="prd-record__ring"></div>
    <div className="prd-record__disc">
      <div className="prd-record__inner-circle"></div>
    </div>
  </div>
);

// ---- Journal row mimicking JournalLogRow.swift -------------------------
const JournalRow = ({ entry }) => {
  const mood = (entry.mood || "").toLowerCase();
  const moodCfg = MOOD_COLORS[mood] || { c: "var(--ink-3)" };
  const railColor = mood ? moodCfg.c : "var(--ink-3)";
  const isVoice = entry.kind === "voice";
  return (
    <div className="prd-journal-row" onClick={entry.onOpen}>
      <div className="prd-journal-row__rail" style={{ background: railColor }}></div>
      <div>
        <div style={{ display: "flex", alignItems: "baseline", gap: 12 }}>
          <div className="prd-journal-row__day" style={{ flex: 1 }}>{entry.day.toUpperCase()}</div>
          <span
            className="prd-journal-row__indicator"
            style={{ color: isVoice ? "var(--coral)" : "var(--ink-3)" }}
          >
            {isVoice ? (
              <React.Fragment>
                <svg width="9" height="9" viewBox="0 0 9 9" aria-hidden="true">
                  <polygon points="1.5,0.8 8,4.5 1.5,8.2" fill="currentColor"/>
                </svg>
                VOICE · {entry.duration}
              </React.Fragment>
            ) : "TEXT ONLY"}
          </span>
        </div>
        <div className="prd-journal-row__meta">{entry.meta}</div>
        <div className="prd-journal-row__body">
          {"\u201C"}{entry.body}{"\u201D"}
        </div>
        {mood && (
          <div className="prd-journal-row__mood" style={{ color: moodCfg.c }}>
            {mood}
          </div>
        )}
      </div>
    </div>
  );
};

// ---- Mock journal data -------------------------------------------------
const MOCK_JOURNAL = [
  {
    id: "j1", kind: "voice", duration: "2:34",
    day: "Tuesday",
    meta: "MAY 5  ·  TEMPO  ·  7.0 MI",
    body: "Hit splits within two seconds either way. Felt smooth through five then the wind picked up on the back stretch. Calf was quiet today, which I noticed.",
    mood: "positive",
  },
  {
    id: "j2", kind: "voice", duration: "3:18",
    day: "Sunday",
    meta: "MAY 3  ·  LONG RUN  ·  18.0 MI",
    body: "Long one. Coffee then out the door at 6:30. Heavy first three miles, then it loosened up — last four were the strongest. Wanted ice afterward but didn't.",
    mood: "tired",
  },
  {
    id: "j3", kind: "text",
    day: "Friday",
    meta: "MAY 2  ·  RECOVERY  ·  4.0 MI",
    body: "Easy shakeout. Knee felt a touch warm in the first mile, settled by the second. Keeping it short — no need to push anything today.",
    mood: "neutral",
  },
  {
    id: "j4", kind: "voice", duration: "1:47",
    day: "Wednesday",
    meta: "APR 30  ·  INTERVALS  ·  8.6 MI",
    body: "Six by 800. The third was the keeper — felt the rhythm finally click. Recoveries were too short, I'll fix that next time. Quads tired tonight.",
    mood: "positive",
  },
];

// ---- Format a duration in m:ss -----------------------------------------
const fmtDuration = (s) => `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;

// ---- The screen --------------------------------------------------------
const LogScreen = ({ onOpenPicker, onOpenEntry }) => {
  const [mode, setMode] = React.useState("run"); // "run" | "checkin"
  const [isRecording, setIsRecording] = React.useState(false);
  const [duration, setDuration] = React.useState(0);
  const [notes, setNotes] = React.useState("");
  const [linkedWorkout, setLinkedWorkout] = React.useState({
    date: "MAY 5", dist: "7.00 mi", time: "44:08", pace: "6:18 / MI", source: "APPLE WATCH",
  });

  // Tick recording duration
  React.useEffect(() => {
    if (!isRecording) return;
    const t = setInterval(() => setDuration(d => d + 1), 1000);
    return () => clearInterval(t);
  }, [isRecording]);

  const toggleRecord = () => {
    if (isRecording) {
      // Stop — in a real app we'd open the confirmation sheet
      setIsRecording(false);
      setDuration(0);
    } else {
      setDuration(0);
      setIsRecording(true);
    }
  };

  const isCheckIn = mode === "checkin";

  return (
    <div className="page">
      <style>{RECORD_PULSE_CSS}</style>
      <PlateStrip surface="LOG · v1 VOICE LOG" fig="FIG. 09" />

      {/* page__body has 24px horizontal padding; we counter it on
          full-bleed elements with negative horizontal margins. */}
      <div className="page__body" style={{ padding: 0 }}>
        {/* ---- Mode toggle (full-bleed) ---- */}
        <div className="prd-mode" style={{ marginTop: 14 }}>
          <button
            className={"prd-mode__btn" + (!isCheckIn ? " is-active" : "")}
            onClick={() => setMode("run")}
          >
            Log run
            <div className="prd-mode__rail"></div>
          </button>
          <button
            className={"prd-mode__btn" + (isCheckIn ? " is-active" : "")}
            onClick={() => { setMode("checkin"); setLinkedWorkout(null); }}
          >
            Check in
            <div className="prd-mode__rail"></div>
          </button>
        </div>

        {/* ---- Title block ---- */}
        <div style={{ padding: "32px 24px 24px 24px", textAlign: "center" }}>
          {isRecording ? (
            <div
              className="h-display"
              style={{
                fontSize: 56,
                fontFamily: "var(--font-mono)",
                fontVariantNumeric: "tabular-nums",
                letterSpacing: "-0.02em",
              }}
            >
              {fmtDuration(duration)}
            </div>
          ) : (
            <h1 className="h-display" style={{ fontSize: 38, margin: 0 }}>
              {isCheckIn ? "How are you feeling?" : "Log your run."}
            </h1>
          )}
          <p style={{
            fontFamily: "var(--font-body)",
            fontStyle: "italic",
            fontSize: 15,
            color: "var(--ink-2)",
            margin: "14px 0 0 0",
            lineHeight: 1.4,
          }}>
            {isRecording
              ? (isCheckIn
                  ? "Speak your status — tap the button to stop."
                  : "Recording — tap the button to stop.")
              : (isCheckIn
                  ? "Tap the button to record a quick check-in."
                  : "Tap the button to start your voice memo.")}
          </p>
        </div>

        {/* ---- Linked workout (run mode only) ---- */}
        {!isCheckIn && (
          <div
            className="prd-hl-section prd-hl-section--clickable"
            style={{ borderTop: "1px solid var(--rule)" }}
            onClick={onOpenPicker}
          >
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
              <Eyebrow>LINKED TO</Eyebrow>
              <span style={{
                fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 500,
                letterSpacing: "0.10em", color: "var(--ink-2)",
                textTransform: "uppercase",
              }}>
                {linkedWorkout ? "CHANGE" : "LINK A RUN"} ↗
              </span>
            </div>
            {linkedWorkout ? (
              <div style={{ marginTop: 8 }}>
                <div className="h-display" style={{ fontSize: 20 }}>
                  {linkedWorkout.date}  ·  {linkedWorkout.dist}  ·  {linkedWorkout.time}
                </div>
                <div style={{
                  fontFamily: "var(--font-mono)", fontSize: 10,
                  color: "var(--ink-3)", letterSpacing: "0.10em",
                  marginTop: 4,
                }}>
                  {linkedWorkout.pace}   ·   {linkedWorkout.source}
                </div>
              </div>
            ) : (
              <div style={{
                fontFamily: "var(--font-body)", fontStyle: "italic",
                fontSize: 14, color: "var(--ink-2)", marginTop: 6,
              }}>
                Optional — attach to a recent run.
              </div>
            )}
          </div>
        )}

        {/* ---- Record button — the one loud accent ---- */}
        <div style={{
          display: "flex", flexDirection: "column", alignItems: "center",
          gap: 18, padding: "56px 24px 56px 24px",
        }}>
          <RecordButton isRecording={isRecording} onClick={toggleRecord} />
          <div style={{
            fontFamily: "var(--font-mono)", fontSize: 11, fontWeight: 500,
            letterSpacing: "0.14em", color: "var(--ink-2)",
            textTransform: "uppercase",
          }}>
            {isRecording ? "Tap to stop" : "Tap to record"}
          </div>
        </div>

        {/* ---- Type notes ---- */}
        <div
          className="prd-hl-section"
          style={{ borderTop: "1px solid var(--rule)" }}
        >
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
            <Eyebrow>OR  ·  TYPE NOTES</Eyebrow>
            <span style={{
              fontFamily: "var(--font-mono)", fontSize: 11, fontWeight: 500,
              letterSpacing: "0.12em",
              color: notes.trim() ? "var(--coral)" : "var(--ink-3)",
              textTransform: "uppercase",
              cursor: notes.trim() ? "pointer" : "default",
            }}>
              {notes.trim() ? "SAVE ↗" : "SAVE"}
            </span>
          </div>
          <textarea
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            placeholder="How did your run feel today?"
            style={{
              width: "100%", marginTop: 10,
              minHeight: 88,
              background: "transparent", border: 0, outline: "none", resize: "none",
              fontFamily: "var(--font-body)",
              fontStyle: notes ? "normal" : "italic",
              fontSize: 15, lineHeight: 1.5,
              color: "var(--ink)",
              padding: 0,
              boxSizing: "border-box",
            }}
          />
        </div>

        {/* ---- Journal feed ---- */}
        <div style={{
          display: "flex", justifyContent: "space-between", alignItems: "baseline",
          padding: "20px 24px 14px 24px",
          borderBottom: "1px solid var(--rule)",
        }}>
          <Eyebrow>JOURNAL  ·  {MOCK_JOURNAL.length} ENTRIES</Eyebrow>
          <span style={{
            fontFamily: "var(--font-mono)", fontSize: 11, fontWeight: 500,
            letterSpacing: "0.12em", color: "var(--ink-2)", cursor: "pointer",
            textTransform: "uppercase",
          }}>
            ↻
          </span>
        </div>
        {MOCK_JOURNAL.map(e => <JournalRow key={e.id} entry={{ ...e, onOpen: onOpenEntry }} />)}

        <div style={{ height: 40 }}></div>
      </div>
    </div>
  );
};

window.LogScreen = LogScreen;

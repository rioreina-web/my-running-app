// Post Run Drip · iOS UI kit · Coach screen (chat thread + weekly report)
//
// Mirrors CoachView.swift — message thread with WelcomeCard when empty,
// CoachQuote bubbles for the coach (italic serif, coral left bar),
// plain right-aligned text for the athlete. Input bar pinned at bottom.

const COACH_CSS = `
.prd-coach__msg-coach {
  margin: 6px 0 0 0;
}
.prd-coach__msg-you {
  align-self: flex-end;
  max-width: 86%;
  font-family: var(--font-body);
  font-size: 14px; line-height: 1.5;
  color: var(--ink);
  background: var(--card);
  border-radius: 12px 12px 4px 12px;
  padding: 10px 14px;
  box-shadow: 0 2px 8px rgba(0,0,0,0.06);
}
.prd-coach__timestamp {
  font-family: var(--font-mono);
  font-size: 9px; font-weight: 500;
  letter-spacing: 0.10em;
  color: var(--ink-3);
  text-transform: uppercase;
}
.prd-coach__input {
  display: grid;
  grid-template-columns: 1fr 36px;
  gap: 10px;
  align-items: center;
  padding: 12px 24px 0 24px;
  border-top: 1px solid var(--rule);
  background: var(--paper);
}
.prd-coach__input-field {
  background: var(--card);
  border-radius: 18px;
  padding: 9px 14px;
  font-family: var(--font-body);
  font-size: 14px; color: var(--ink);
  border: 1px solid transparent;
  outline: none;
  width: 100%; box-sizing: border-box;
}
.prd-coach__input-field:focus { outline: 2px solid var(--coral); }
.prd-coach__send {
  width: 36px; height: 36px;
  border-radius: 999px;
  background: var(--coral);
  display: grid; place-items: center;
  cursor: pointer;
  transition: background .15s ease-out;
}
.prd-coach__send:hover { background: var(--coral-deep); }
.prd-coach__send svg { width: 16px; height: 16px; fill: #fff; }

.prd-coach__chips {
  display: flex; gap: 8px; padding: 6px 0 12px 0;
  flex-wrap: wrap;
}
.prd-coach__chip {
  font-family: var(--font-display);
  font-size: 13px; font-weight: 500;
  color: var(--ink);
  border: 1px solid var(--rule);
  background: var(--card);
  border-radius: 999px;
  padding: 6px 12px;
  cursor: pointer;
  white-space: nowrap;
}
.prd-coach__chip:hover { border-color: var(--coral); color: var(--coral); }
`;

// The first weekly-report quote lives in the report card above the
// thread — so the thread starts with the athlete's reply, not a
// duplicate of the report.
const MOCK_THREAD = [
  {
    id: "m1", role: "you", ts: "MON · 7:42 AM",
    text: "Drop Tuesday's tempo if the knee's still grumbly?",
  },
  {
    id: "m2", role: "coach", ts: "MON · 8:10 AM",
    text: "Swap it for an easy 6. Three more tempos before taper — losing one is fine.",
  },
  {
    id: "m3", role: "you", ts: "MON · 9:14 AM",
    text: "Done. Will report back.",
  },
];

const SUGGESTED_CHIPS = [
  "How's my training going?",
  "Plan tomorrow's run.",
  "Read this week's report.",
  "Am I overtraining?",
];

const CoachScreen = ({ onOpenReport }) => {
  const [thread, setThread] = React.useState(MOCK_THREAD);
  const [input, setInput] = React.useState("");
  const scrollerRef = React.useRef(null);

  const send = () => {
    const t = input.trim();
    if (!t) return;
    setThread(m => [
      ...m,
      { id: "m" + (m.length + 1), role: "you", ts: "NOW", text: t },
    ]);
    setInput("");
    // Simulate coach reply
    setTimeout(() => {
      setThread(m => [...m, {
        id: "m" + (m.length + 1), role: "coach", ts: "NOW",
        text: "Noted. I'll look at the week and circle back tonight.",
      }]);
    }, 900);
  };

  React.useEffect(() => {
    if (scrollerRef.current) {
      scrollerRef.current.scrollTop = scrollerRef.current.scrollHeight;
    }
  }, [thread.length]);

  return (
    <div className="page">
      <style>{COACH_CSS}</style>
      <PlateStrip surface="COACH · CONVERSATION" fig="FIG. 14" />

      <div className="page__body" ref={scrollerRef} style={{ display: "flex", flexDirection: "column", padding: 0 }}>
        {/* Weekly report card — the page's main object. No title above. */}
        <div style={{ padding: "14px 24px 0 24px" }}>
          <div className="card" onClick={onOpenReport} style={{ padding: 16, cursor: "pointer" }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
              <Eyebrow coral>WEEKLY REPORT · WK 17</Eyebrow>
              <span style={{
                fontFamily: "var(--font-mono)", fontSize: 10,
                color: "var(--ink-3)", letterSpacing: "0.10em",
              }}>4 MIN ↗</span>
            </div>
            <h2 className="h-display" style={{ fontSize: 24, marginTop: 8 }}>The base is taking.</h2>
            <p className="quote" style={{ marginTop: 6, marginBottom: 0, fontSize: 14, color: "var(--ink-2)" }}>
              Three good weeks. Hold the volume.
            </p>
          </div>
        </div>

        {/* Thread */}
        <div style={{ padding: "22px 24px 14px 24px", display: "flex", flexDirection: "column", gap: 12 }}>
          {thread.map(m => (
            <div key={m.id}
              style={{
                display: "flex", flexDirection: "column",
                alignItems: m.role === "you" ? "flex-end" : "stretch",
              }}
            >
              <div className="prd-coach__timestamp" style={{ marginBottom: 4 }}>
                {m.role === "coach" ? "COACH · " : "YOU · "}{m.ts}
              </div>
              {m.role === "coach" ? (
                <CoachQuote>{m.text}</CoachQuote>
              ) : (
                <div className="prd-coach__msg-you">{m.text}</div>
              )}
            </div>
          ))}
        </div>

        {/* Suggested chips */}
        <div style={{ padding: "0 24px" }}>
          <div className="prd-coach__chips">
            {SUGGESTED_CHIPS.map((c, i) => (
              <span key={i} className="prd-coach__chip" onClick={() => setInput(c)}>{c}</span>
            ))}
          </div>
        </div>

        <div style={{ flex: 1 }} />

        {/* Input bar */}
        <div className="prd-coach__input" style={{ paddingBottom: 14 }}>
          <input
            className="prd-coach__input-field"
            placeholder="Write to your coach…"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter") send(); }}
          />
          <div className="prd-coach__send" onClick={send} role="button" aria-label="Send">
            <svg viewBox="0 0 16 16">
              <path d="M2 8L13 2.5L9.5 8L13 13.5L2 8Z" />
            </svg>
          </div>
        </div>
      </div>
    </div>
  );
};

window.CoachScreen = CoachScreen;

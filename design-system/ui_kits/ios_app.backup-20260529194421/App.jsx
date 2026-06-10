// Post Run Drip · iOS UI kit · App orchestrator
// Renders an iOS frame with one of the screens inside,
// plus a tab bar at the bottom for navigation.

const App = () => {
  const [signedIn, setSignedIn] = React.useState(true);
  const [tab, setTab] = React.useState("log");
  const [sheet, setSheet] = React.useState(null); // "workout" | "injuries" | null

  // The "Log" tab is the Today (diary+charts) screen
  let body;
  if (sheet === "workout")        body = <WorkoutDetailScreen onClose={() => setSheet(null)} />;
  else if (sheet === "injuries")  body = <InjuriesScreen onClose={() => setSheet(null)} />;
  else if (tab === "log")         body = <TodayScreen />;
  else if (tab === "train")       body = <TrainingScreen />;
  else if (tab === "trends")      body = <TrendsPlaceholder onOpenWorkout={() => setSheet("workout")} onOpenInjuries={() => setSheet("injuries")} />;
  else if (tab === "coach")       body = <CoachPlaceholder />;
  else                            body = <RunsPlaceholder onOpenWorkout={() => setSheet("workout")} />;

  if (!signedIn) {
    return (
      <IOSDevice width={390} height={844}>
        <div style={{ paddingTop: 62, height: "100%", boxSizing: "border-box", background: "#F5F3F0" }}>
          <SignInScreen onSignIn={() => setSignedIn(true)} />
        </div>
      </IOSDevice>
    );
  }

  return (
    <IOSDevice width={390} height={844}>
      <div style={{ paddingTop: 62, paddingBottom: 34, height: "100%", boxSizing: "border-box", display: "flex", flexDirection: "column", background: "#F5F3F0" }}>
        <div style={{ flex: 1, overflow: "hidden" }}>{body}</div>
        {!sheet && <TabBar active={tab} onChange={setTab} />}
      </div>
    </IOSDevice>
  );
};

// ---- Lightweight placeholder screens for tabs we didn't fully build ----

const TrendsPlaceholder = ({ onOpenWorkout, onOpenInjuries }) => (
  <div className="page">
    <PlateStrip surface="TRENDS · v1 ANALYTICS SURFACE" fig="FIG. 1" />
    <div className="page__body">
      <div className="section section--first">
        <Eyebrow coral>OPENING FIGURE</Eyebrow>
        <h1 className="h-display" style={{ fontSize: 32 }}>The 5-second view.</h1>
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10, marginTop: 14 }}>
        <StatTile label="VOLUME · 7D" value="47.2" unit="MI" delta="+8%  vs 4-WK AVG" />
        <StatTile label="FITNESS"     value="3:14" unit="FULL" delta="−47s  vs 4 WEEKS AGO" />
        <StatTile label="LOAD · ACWR" value="1.18" unit="RATIO" delta="PRODUCTIVE" />
        <StatTile label="INJURY RISK" value="2.4"  unit="/ 10"  delta="LOW · 4W AVG 2.1" />
      </div>

      <Section eyebrow="FITNESS · 12-WEEK PROGRESSION" eyebrowRight="TAP TO EXPAND ↗">
        <div className="card" style={{ padding: 14, marginTop: 6 }}>
          <div style={{ display: "flex", justifyContent: "flex-end" }}>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)", letterSpacing: "0.10em" }}>GOAL  3:10</span>
          </div>
          <LineChart data={[230, 226, 222, 220, 218, 214, 212, 209, 206, 202, 198, 195]} height={70} />
        </div>
      </Section>

      <Section eyebrow="LOAD · WEEKLY VOLUME × ACWR">
        <div className="card" style={{ padding: 14, marginTop: 6 }}>
          <div style={{ display: "flex", gap: 4, alignItems: "flex-end", height: 64 }}>
            {[28, 30, 26, 32, 36, 38, 34, 42, 44, 40, 46, 44, 47].map((h, i) => (
              <div key={i} style={{ flex: 1, height: h * 1.2, background: i === 12 ? "var(--ink)" : "var(--ink-3)", opacity: i === 12 ? 1 : 0.6, borderRadius: "1px 1px 0 0" }}></div>
            ))}
          </div>
          <div style={{ textAlign: "right", marginTop: 6, fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--coral)", letterSpacing: "0.10em" }}>ACWR 1.18</div>
        </div>
      </Section>

      <Section eyebrow="DRILL DOWN">
        <div style={{ display: "flex", flexDirection: "column", gap: 0 }}>
          <a className="link" onClick={onOpenWorkout} style={{ borderColor: "var(--rule)", color: "var(--ink)", padding: "12px 0", display: "block" }}>
            ↗ &nbsp;Open last workout — May 7 · 5.01 mi
          </a>
          <a className="link" onClick={onOpenInjuries} style={{ borderColor: "var(--rule)", color: "var(--ink)", padding: "12px 0", display: "block" }}>
            ↗ &nbsp;Active aches — 2 tracking
          </a>
        </div>
      </Section>
    </div>
  </div>
);

const CoachPlaceholder = () => (
  <div className="page">
    <PlateStrip surface="COACH · CONVERSATION" fig="FIG. 14" />
    <div className="page__body">
      <div className="section section--first">
        <Eyebrow coral>COACH</Eyebrow>
        <h1 className="h-display" style={{ fontSize: 30 }}>Your week, in plain language.</h1>
        <p className="body-sm" style={{ marginTop: 8 }}>Your coach reviews your log every Sunday night and leaves a note. Ask follow-ups any time.</p>
      </div>

      <div style={{ marginTop: 18, display: "flex", flexDirection: "column", gap: 14 }}>
        <div>
          <Eyebrow coral>FROM YOUR COACH · SUNDAY EVENING</Eyebrow>
          <CoachQuote>
            Three good weeks in a row — your easy paces have settled a beat slower without losing fitness. That's the sign the aerobic base is taking. Hold the volume; the next test is Wednesday's MP block.
          </CoachQuote>
        </div>
        <Hairline />
        <div>
          <Eyebrow>YOU · MONDAY 7:42 AM</Eyebrow>
          <p className="body" style={{ marginTop: 4, marginBottom: 0 }}>Should I drop Tuesday's tempo if the knee is still grumbly?</p>
        </div>
        <Hairline />
        <div>
          <Eyebrow coral>COACH · MONDAY 8:10 AM</Eyebrow>
          <CoachQuote>
            Swap it for an easy 6. We have three more tempos before taper — losing one to be honest with the body is fine. Update me Tuesday night.
          </CoachQuote>
        </div>
      </div>

      <div style={{ marginTop: 22 }}>
        <input className="field" placeholder="Write to your coach…" />
      </div>
    </div>
  </div>
);

const RunsPlaceholder = ({ onOpenWorkout }) => {
  const runs = [
    { d: "MAY 7", t: "EASY",     m: "5.01 MI", p: "7:11" },
    { d: "MAY 5", t: "TEMPO",    m: "11.0 MI", p: "6:18" },
    { d: "MAY 3", t: "LONG RUN", m: "18.0 MI", p: "7:32" },
    { d: "MAY 2", t: "RECOVERY", m: "4.0 MI",  p: "8:14" },
    { d: "APR 30", t: "INTERVALS", m: "8.6 MI", p: "6:42" },
    { d: "APR 28", t: "EASY",    m: "6.0 MI",  p: "7:38" },
  ];
  return (
    <div className="page">
      <PlateStrip surface="HISTORY · ALL RUNS" fig="FIG. 19" />
      <div className="page__body">
        <div className="section section--first">
          <Eyebrow coral>HISTORY</Eyebrow>
          <h1 className="h-display" style={{ fontSize: 30 }}>Every run, indexed.</h1>
        </div>
        <Hairline style={{ marginTop: 14 }} />
        {runs.map((r, i) => (
          <div key={i} onClick={i === 0 ? onOpenWorkout : undefined} style={{ display: "grid", gridTemplateColumns: "70px 1fr 60px", alignItems: "center", padding: "16px 0", borderBottom: "1px solid var(--rule)", cursor: i === 0 ? "pointer" : "default" }}>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--ink-2)", letterSpacing: "0.10em" }}>{r.d}</span>
            <div>
              <div style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-2)", letterSpacing: "0.10em", textTransform: "uppercase" }}>{r.t}</div>
              <div style={{ fontFamily: "var(--font-display)", fontSize: 18, color: "var(--ink)", fontWeight: 700 }}>{r.m}</div>
            </div>
            <span style={{ fontFamily: "var(--font-mono)", fontWeight: 600, fontSize: 14, color: i === 0 ? "var(--coral)" : "var(--ink)" }}>{r.p}</span>
          </div>
        ))}
      </div>
    </div>
  );
};

window.App = App;
window.TrendsPlaceholder = TrendsPlaceholder;
window.CoachPlaceholder = CoachPlaceholder;
window.RunsPlaceholder = RunsPlaceholder;

// Mount
const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(<App />);

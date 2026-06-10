// Post Run Drip · iOS UI kit · Today screen (Plate 18 — Diary + Charts)

const TodayScreen = () => {
  const [mood, setMood] = React.useState(null);
  return (
    <div className="page">
      <PlateStrip surface="LOG · v1 DIARY + CHARTS" fig="FIG. 18" />

      <div className="page__body">
        {/* Date header */}
        <div className="section section--first">
          <Eyebrow coral>TUESDAY</Eyebrow>
          <h1 className="h-display" style={{ fontSize: 34 }}>May 5th.</h1>
          <div style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13, color: "var(--ink-3)" }}>
            — eleven weeks to the marathon. —
          </div>
        </div>

        <div style={{ height: 18 }} />
        <EditorialRule />

        {/* From your coach */}
        <Section eyebrow="FROM YOUR COACH" eyebrowCoral>
          <CoachQuote>The 7-mile MP block — second of three this cycle. Hold splits, don't chase them. Negative is fine, positive is not.</CoachQuote>
          <div style={{ display: "flex", justifyContent: "space-between", marginTop: 8, alignItems: "baseline" }}>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-3)", letterSpacing: "0.10em", textTransform: "uppercase" }}>2 days ago</span>
            <span className="link" style={{ fontSize: 12, whiteSpace: "nowrap" }}>Mark read</span>
          </div>
        </Section>

        <div style={{ height: 18 }} />

        {/* Today · How are you feeling? */}
        <Section eyebrow="TODAY">
          <h2 className="h-display" style={{ fontSize: 20 }}>How are you feeling?</h2>
          <MoodRadio value={mood} onChange={setMood} />
        </Section>

        <div style={{ height: 20 }} />
        <EditorialRule />

        {/* Yesterday journal */}
        <Section eyebrow="SUNDAY · APR 26">
          <h2 className="h-display" style={{ fontSize: 22 }}>Tempo, 6.5 mi.</h2>
          <div style={{ fontFamily: "var(--font-mono)", fontSize: 10, letterSpacing: "0.08em", color: "var(--ink-2)", textTransform: "uppercase", marginTop: 2 }}>
            7:25 / mi&nbsp;&nbsp;·&nbsp;&nbsp;48 MIN&nbsp;&nbsp;·&nbsp;&nbsp;<span style={{ color: MOOD_COLORS.positive.c }}>POSITIVE</span>
          </div>
          <p className="quote" style={{ fontSize: 14, marginTop: 12, marginBottom: 0 }}>
            "Felt good through the warm-up — legs were heavy first mile but loosened up. Tempo blocks smoother than two weeks ago."
          </p>
        </Section>

        <div style={{ height: 24 }} />

        {/* Tomorrow */}
        <Section eyebrow="TOMORROW" eyebrowRight="FROM YOUR COACH">
          <h2 className="h-display" style={{ fontSize: 22 }}>Tempo, 8 miles.</h2>
          <div style={{ fontFamily: "var(--font-mono)", fontSize: 10, letterSpacing: "0.08em", color: "var(--ink-2)", textTransform: "uppercase", marginTop: 2 }}>
            2 mi WU · 5 mi at 7:00 / mi · 1 mi CD
          </div>
          <p className="quote" style={{ fontSize: 14, marginTop: 10, marginBottom: 0 }}>
            "Consistent splits, not negative. Let the rhythm settle."
          </p>
        </Section>

        <div style={{ height: 24 }} />
        <EditorialRule />

        {/* Fitness trend */}
        <Section eyebrow="FITNESS · 12 WEEKS" eyebrowRight="PREDICTED MARATHON">
          <div className="card" style={{ padding: 14, marginTop: 6 }}>
            <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 4 }}>
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--ink)", fontWeight: 600 }}>3:15</span>
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--mood-energized)", letterSpacing: "0.10em", textTransform: "uppercase" }}>→ FITNESS UP</span>
            </div>
            <LineChart data={[195*60+30, 195*60+10, 195*60-5, 194*60+40, 194*60+20, 194*60, 193*60+30, 193*60+0, 192*60+30, 192*60, 191*60+30, 195]} height={70} />
            <div style={{ display: "flex", justifyContent: "space-between", marginTop: 4 }}>
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)", letterSpacing: "0.10em", textTransform: "uppercase" }}>12W AGO</span>
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--coral)", letterSpacing: "0.10em", textTransform: "uppercase" }}>NOW</span>
            </div>
          </div>
        </Section>

        {/* Zone shifts */}
        <Section eyebrow="ZONE SHIFTS · WEEK vs 4 WK AVG">
          <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 8, paddingTop: 4 }}>
            {[
              { l: "EASY",      v: "62%", d: "+4", color: "var(--ink-2)" },
              { l: "MODERATE",  v: "22%", d: "−2", color: "var(--ink-2)" },
              { l: "THRESHOLD", v: "9%",  d: "+1", color: "var(--coral)" },
              { l: "HARD",      v: "7%",  d: "−3", color: "var(--ink-2)" },
            ].map(z => (
              <div key={z.l} style={{ textAlign: "center" }}>
                <div style={{ fontFamily: "var(--font-mono)", fontSize: 9, letterSpacing: "0.10em", color: z.color, textTransform: "uppercase" }}>{z.l}</div>
                <div style={{ fontFamily: "var(--font-mono)", fontWeight: 600, fontSize: 20, color: "var(--ink)", marginTop: 4 }}>{z.v}</div>
                <div style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--mood-energized)", marginTop: 2 }}>{z.d}</div>
              </div>
            ))}
          </div>
        </Section>

        <div style={{ height: 20 }} />

        {/* Race predictions */}
        <Section eyebrow="RACE PREDICTIONS" eyebrowRight="MEDIUM CONFIDENCE">
          <div className="race-strip">
            {[
              { l: "MILE", v: "5:42", d: "−4s" },
              { l: "5K",   v: "18:52", d: "−14s" },
              { l: "10K",  v: "39:11", d: "−24s" },
              { l: "HALF", v: "1:27",  d: "−47s" },
              { l: "FULL", v: "3:15",  d: "−1:24" },
            ].map(r => (
              <div key={r.l} className="rcell">
                <span className="rlbl">{r.l}</span>
                <span className="rval">{r.v}</span>
                <span className="rdel">{r.d}</span>
              </div>
            ))}
          </div>
        </Section>

        <div style={{ height: 24 }} />
      </div>
    </div>
  );
};

window.TodayScreen = TodayScreen;

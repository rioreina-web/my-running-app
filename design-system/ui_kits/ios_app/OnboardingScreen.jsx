// Post Run Drip · iOS UI kit · Onboarding flow (4 steps)
//
// Editorial-mode rebuild of OnboardingView.swift. Same 4 steps:
// (1) Welcome   (2) Connect data   (3) Set a goal   (4) Ready.
// Replaces SF-Symbol-and-rounded-pill style with hairline-bound
// editorial vocabulary: monospaced labels, Crimson Pro display,
// coral progress dots only.

const ONBOARDING_CSS = `
.prd-onb {
  background: var(--paper);
  width: 100%; height: 100%;
  display: flex; flex-direction: column;
  padding: 32px 0 28px 0;
  box-sizing: border-box;
}
.prd-onb__progress {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 6px;
  padding: 0 56px;
}
.prd-onb__progress > span {
  height: 2px; border-radius: 999px;
  background: var(--rule);
  transition: background .25s ease-out;
}
.prd-onb__progress > span.is-on { background: var(--coral); }

.prd-onb__body {
  flex: 1;
  display: flex; flex-direction: column;
  padding: 28px 32px 0 32px;
  min-height: 0;
}

.prd-onb__plate-strip {
  display: flex; justify-content: space-between;
  font-family: var(--font-mono); font-size: 10px;
  letter-spacing: 0.14em; color: var(--ink-2);
  text-transform: uppercase;
  padding: 0 32px 12px 32px;
}

.prd-onb__eyebrow {
  font-family: var(--font-mono);
  font-size: 10px; font-weight: 500;
  letter-spacing: 0.14em; color: var(--coral);
  text-transform: uppercase;
}
.prd-onb__title {
  font-family: var(--font-display);
  font-weight: 700; color: var(--ink);
  letter-spacing: -0.01em; line-height: 1.05;
  font-size: 38px;
  margin: 6px 0 0 0;
}
.prd-onb__sub {
  font-family: var(--font-body); font-style: italic;
  font-size: 14px; color: var(--ink-2);
  line-height: 1.55;
  margin: 12px 0 0 0;
}

.prd-onb__feature {
  display: grid;
  grid-template-columns: 28px 1fr;
  gap: 14px;
  padding: 18px 0;
  border-top: 1px solid var(--rule);
}
.prd-onb__feature:last-child { border-bottom: 1px solid var(--rule); }
.prd-onb__feature-num {
  font-family: var(--font-mono);
  font-size: 10px; font-weight: 500;
  letter-spacing: 0.10em; color: var(--coral);
  padding-top: 2px;
}
.prd-onb__feature-title {
  font-family: var(--font-display);
  font-size: 16px; font-weight: 700;
  color: var(--ink); letter-spacing: -0.01em;
}
.prd-onb__feature-desc {
  font-family: var(--font-body);
  font-size: 13px; color: var(--ink-2); line-height: 1.5;
  margin-top: 3px;
}

.prd-onb__row {
  padding: 14px 0;
  border-top: 1px solid var(--rule);
  display: flex; justify-content: space-between; align-items: center;
}
.prd-onb__row:last-child { border-bottom: 1px solid var(--rule); }
.prd-onb__row-label {
  font-family: var(--font-display);
  font-size: 15px; font-weight: 600; color: var(--ink);
}
.prd-onb__row-hint {
  font-family: var(--font-body); font-style: italic;
  font-size: 12px; color: var(--ink-3);
  display: block; margin-top: 2px;
}
.prd-onb__row-action {
  font-family: var(--font-mono);
  font-size: 11px; font-weight: 500;
  letter-spacing: 0.12em;
  color: var(--coral);
  text-transform: uppercase;
  cursor: pointer;
}
.prd-onb__row-action.is-on { color: var(--mood-energized, #2D8A4E); }

.prd-onb__chip-row {
  display: flex; flex-wrap: wrap; gap: 8px; margin-top: 14px;
}
.prd-onb__chip {
  font-family: var(--font-mono); font-size: 11px; font-weight: 500;
  letter-spacing: 0.12em;
  padding: 8px 14px; border-radius: 999px;
  border: 1px solid var(--rule);
  background: var(--card);
  color: var(--ink-2);
  cursor: pointer;
  text-transform: uppercase;
}
.prd-onb__chip.is-active {
  background: transparent; color: var(--coral); border-color: var(--coral);
}

.prd-onb__time {
  display: grid;
  grid-template-columns: 60px 12px 60px 12px 60px;
  gap: 6px; align-items: center;
  margin-top: 14px;
  font-family: var(--font-mono);
  font-variant-numeric: tabular-nums;
}
.prd-onb__time-col {
  display: flex; flex-direction: column;
  align-items: center;
  padding: 6px 0;
  background: var(--card);
  border-radius: 10px;
}
.prd-onb__time-col select {
  appearance: none; -webkit-appearance: none;
  background: transparent; border: 0; outline: 0;
  font-family: var(--font-mono);
  font-size: 22px; font-weight: 600;
  color: var(--ink);
  text-align: center; text-align-last: center;
  width: 100%; padding: 4px 0;
}
.prd-onb__time-col label {
  font-family: var(--font-mono);
  font-size: 9px; letter-spacing: 0.12em;
  color: var(--ink-3);
  text-transform: uppercase;
}
.prd-onb__time-colon {
  font-family: var(--font-display);
  font-size: 22px; color: var(--ink-3);
  text-align: center;
}

.prd-onb__foot {
  padding: 18px 32px 0 32px;
  display: flex; flex-direction: column; gap: 12px;
}
.prd-onb__skip {
  text-align: center;
  font-family: var(--font-mono);
  font-size: 11px; letter-spacing: 0.12em;
  color: var(--ink-3); cursor: pointer;
  text-transform: uppercase;
  padding: 6px 0;
}

.prd-onb__tip {
  display: grid;
  grid-template-columns: 28px 1fr;
  gap: 14px;
  padding: 14px 0;
  border-top: 1px solid var(--rule);
  align-items: baseline;
}
.prd-onb__tip:last-child { border-bottom: 1px solid var(--rule); }
.prd-onb__tip-n {
  font-family: var(--font-mono);
  font-size: 10px; font-weight: 600;
  letter-spacing: 0.10em; color: var(--coral);
}
.prd-onb__tip-text {
  font-family: var(--font-body);
  font-size: 14px; color: var(--ink); line-height: 1.5;
}
`;

const HOURS = Array.from({ length: 6 }, (_, i) => i);
const SIXTY = Array.from({ length: 60 }, (_, i) => i);

const OnboardingScreen = ({ onComplete, onSkipAll }) => {
  const [step, setStep] = React.useState(0);
  const [hk, setHK] = React.useState(false);
  const [strava, setStrava] = React.useState(false);
  const [distance, setDistance] = React.useState("half_marathon");
  const [hh, setHh] = React.useState(1);
  const [mm, setMm] = React.useState(30);
  const [ss, setSs] = React.useState(0);

  const total = 4;
  const next = () => step < total - 1 ? setStep(step + 1) : onComplete && onComplete();
  const back = () => step > 0 && setStep(step - 1);

  return (
    <div className="prd-onb">
      <style>{ONBOARDING_CSS}</style>

      {/* Plate strip — kept editorial */}
      <div className="prd-onb__plate-strip">
        <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
          <span style={{ color: "var(--ink)" }}>RUNNING LOG</span>
          <span>— FIRST-RUN · v1 ONBOARDING</span>
        </div>
        <div style={{ textAlign: "right", display: "flex", flexDirection: "column", gap: 2 }}>
          <span style={{ color: "var(--ink)" }}>STEP {step + 1} / {total}</span>
          <span style={{ cursor: "pointer" }} onClick={onSkipAll}>SKIP ↗</span>
        </div>
      </div>

      {/* Progress strip */}
      <div className="prd-onb__progress">
        {Array.from({ length: total }).map((_, i) => (
          <span key={i} className={i <= step ? "is-on" : ""} />
        ))}
      </div>

      {/* Step bodies */}
      <div className="prd-onb__body">
        {step === 0 && (
          <React.Fragment>
            <div className="prd-onb__eyebrow">WELCOME</div>
            <h1 className="prd-onb__title">A quieter log<br/>for serious runners.</h1>
            <p className="prd-onb__sub">
              — half diary, half cockpit. Talk to it after a run; the coach reads the week. —
            </p>

            <div style={{ marginTop: 22 }}>
              <div className="prd-onb__feature">
                <span className="prd-onb__feature-num">01</span>
                <div>
                  <div className="prd-onb__feature-title">Voice memos.</div>
                  <div className="prd-onb__feature-desc">Tap the coral button. Talk for two minutes. It transcribes, extracts a mood, and saves it to your journal.</div>
                </div>
              </div>
              <div className="prd-onb__feature">
                <span className="prd-onb__feature-num">02</span>
                <div>
                  <div className="prd-onb__feature-title">Glass-box analysis.</div>
                  <div className="prd-onb__feature-desc">Pace, HR zones, splits — and the rationale behind every coaching note. No black boxes.</div>
                </div>
              </div>
              <div className="prd-onb__feature">
                <span className="prd-onb__feature-num">03</span>
                <div>
                  <div className="prd-onb__feature-title">A coach in the room.</div>
                  <div className="prd-onb__feature-desc">Reads your log every Sunday night. Ask follow-ups any time. Reasons in plain language.</div>
                </div>
              </div>
            </div>
          </React.Fragment>
        )}

        {step === 1 && (
          <React.Fragment>
            <div className="prd-onb__eyebrow">DATA · SOURCES</div>
            <h1 className="prd-onb__title">Where do your<br/>runs come from?</h1>
            <p className="prd-onb__sub">
              — Apple Health pulls everything: Garmin, Coros, Strava, the watch on your wrist. Pick what you have. —
            </p>

            <div style={{ marginTop: 22 }}>
              <div className="prd-onb__row">
                <div>
                  <span className="prd-onb__row-label">Apple Health</span>
                  <span className="prd-onb__row-hint">Pulls runs, HR, and sleep automatically.</span>
                </div>
                <span
                  className={"prd-onb__row-action" + (hk ? " is-on" : "")}
                  onClick={() => setHK(!hk)}
                >
                  {hk ? "CONNECTED ✓" : "ALLOW ↗"}
                </span>
              </div>
              <div className="prd-onb__row">
                <div>
                  <span className="prd-onb__row-label">Strava</span>
                  <span className="prd-onb__row-hint">Optional — only if Health misses runs.</span>
                </div>
                <span
                  className={"prd-onb__row-action" + (strava ? " is-on" : "")}
                  onClick={() => setStrava(!strava)}
                >
                  {strava ? "CONNECTED ✓" : "CONNECT ↗"}
                </span>
              </div>
              <div className="prd-onb__row">
                <div>
                  <span className="prd-onb__row-label">Manual entry</span>
                  <span className="prd-onb__row-hint">Always available — no permissions needed.</span>
                </div>
                <span className="prd-onb__row-action" style={{ color: "var(--ink-3)" }}>READY</span>
              </div>
            </div>

            <p className="prd-onb__sub" style={{ fontSize: 12, color: "var(--ink-3)" }}>
              — you can change any of this later. Nothing is collected unless you say so. —
            </p>
          </React.Fragment>
        )}

        {step === 2 && (
          <React.Fragment>
            <div className="prd-onb__eyebrow">A GOAL</div>
            <h1 className="prd-onb__title">What are you<br/>training for?</h1>
            <p className="prd-onb__sub">
              — this anchors the coaching. You can change it any week. —
            </p>

            <div style={{ marginTop: 22 }}>
              <div style={{
                fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 500,
                letterSpacing: "0.14em", color: "var(--ink-3)",
                textTransform: "uppercase",
              }}>DISTANCE</div>
              <div className="prd-onb__chip-row">
                {[
                  { v: "5k", l: "5K" },
                  { v: "10k", l: "10K" },
                  { v: "half_marathon", l: "HALF" },
                  { v: "marathon", l: "MARATHON" },
                  { v: "ultra", l: "ULTRA" },
                  { v: "general", l: "GENERAL FITNESS" },
                ].map(d => (
                  <span
                    key={d.v}
                    className={"prd-onb__chip" + (distance === d.v ? " is-active" : "")}
                    onClick={() => setDistance(d.v)}
                  >
                    {d.l}
                  </span>
                ))}
              </div>
            </div>

            <div style={{ marginTop: 22 }}>
              <div style={{
                fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 500,
                letterSpacing: "0.14em", color: "var(--ink-3)",
                textTransform: "uppercase",
              }}>GOAL TIME · OPTIONAL</div>
              <div className="prd-onb__time">
                <div className="prd-onb__time-col">
                  <select value={hh} onChange={(e) => setHh(parseInt(e.target.value))}>
                    {HOURS.map(h => <option key={h} value={h}>{h}</option>)}
                  </select>
                  <label>HRS</label>
                </div>
                <div className="prd-onb__time-colon">:</div>
                <div className="prd-onb__time-col">
                  <select value={mm} onChange={(e) => setMm(parseInt(e.target.value))}>
                    {SIXTY.map(m => <option key={m} value={m}>{String(m).padStart(2, "0")}</option>)}
                  </select>
                  <label>MIN</label>
                </div>
                <div className="prd-onb__time-colon">:</div>
                <div className="prd-onb__time-col">
                  <select value={ss} onChange={(e) => setSs(parseInt(e.target.value))}>
                    {SIXTY.map(s => <option key={s} value={s}>{String(s).padStart(2, "0")}</option>)}
                  </select>
                  <label>SEC</label>
                </div>
              </div>
            </div>
          </React.Fragment>
        )}

        {step === 3 && (
          <React.Fragment>
            <div className="prd-onb__eyebrow">YOU'RE IN</div>
            <h1 className="prd-onb__title">Three habits.<br/>That's the whole product.</h1>
            <p className="prd-onb__sub">
              — keep these going for a couple of weeks and the coaching gets sharp. —
            </p>

            <div style={{ marginTop: 22 }}>
              <div className="prd-onb__tip">
                <span className="prd-onb__tip-n">01</span>
                <span className="prd-onb__tip-text">After a run, tap the coral button on the LOG tab and talk for a minute.</span>
              </div>
              <div className="prd-onb__tip">
                <span className="prd-onb__tip-n">02</span>
                <span className="prd-onb__tip-text">Check the TRAIN tab in the morning. Read the day's prescription out loud if it helps.</span>
              </div>
              <div className="prd-onb__tip">
                <span className="prd-onb__tip-n">03</span>
                <span className="prd-onb__tip-text">Sunday night, your coach posts a note. Read it. Reply if something is off.</span>
              </div>
            </div>

            <p className="prd-onb__sub" style={{ fontSize: 12, color: "var(--ink-3)", marginTop: 18 }}>
              — that's it. Nothing else to learn. —
            </p>
          </React.Fragment>
        )}
      </div>

      {/* Footer actions */}
      <div className="prd-onb__foot">
        <button
          className="btn btn--primary"
          onClick={next}
        >
          {step < total - 1 ? "Continue" : "Start training ↗"}
        </button>
        {step > 0 && (
          <div className="prd-onb__skip" onClick={back}>← BACK</div>
        )}
      </div>
    </div>
  );
};

window.OnboardingScreen = OnboardingScreen;

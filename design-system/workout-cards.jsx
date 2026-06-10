/* global React, ReactDOM, IOSDevice, DCArtboard, DesignCanvas, DCSection */
/* ════════════════════════════════════════════════════════════════════
   POST RUN DRIP — WORKOUT CARD · directions
   "The card where I go do a workout" — prescribed session screen.
   Four directions, side by side. Pick one to iterate.
   ════════════════════════════════════════════════════════════════════ */

const COACH_QUOTE = "Consistent splits, not negative. Let the rhythm settle.";

const WORKOUT = {
  title: "Tempo, 8 miles.",
  type: "TEMPO",
  intent: "Threshold block · 2 of 3",
  totalMiles: 8.0,
  totalMin: 64,
  steps: [
    { label: "Warm-up",   miles: 2.0, pace: "8:30 / mi", note: "Easy. Settle the breathing." },
    { label: "Tempo",     miles: 5.0, pace: "7:00 / mi", note: "Hold splits. Negative is fine; positive is not.", quality: true },
    { label: "Cool-down", miles: 1.0, pace: "9:00 / mi", note: "Easy. Walk if you need it." },
  ],
  paceTarget: "7:00",
  hrTarget: "152 – 162",
  rpe: "6 / 10",
  prevPrescription: "May 5 · Tempo, 7 mi at 7:00 / mi",
  prevCompletion: "Held 7:02 avg · POSITIVE",
};

/* ════════════════════════════════════════════════════════════════════ */
function App() {
  const phoneSize = { width: 402, height: 874 };
  return (
    <DesignCanvas>
      <DCSection id="primary" title="Workout card · directions" subtitle="Prescribed workout · iOS · pick a direction">
        <DCArtboard id="editorial" label="A · Editorial" width={phoneSize.width} height={phoneSize.height}>
          <Phone><EditorialCard /></Phone>
        </DCArtboard>
        <DCArtboard id="runsheet" label="B · The run sheet" width={phoneSize.width} height={phoneSize.height}>
          <Phone><RunSheetCard /></Phone>
        </DCArtboard>
        <DCArtboard id="cockpit" label="C · Cockpit" width={phoneSize.width} height={phoneSize.height}>
          <Phone><CockpitCard /></Phone>
        </DCArtboard>
        <DCArtboard id="brief" label="D · Brief" width={phoneSize.width} height={phoneSize.height}>
          <Phone><BriefCard /></Phone>
        </DCArtboard>
      </DCSection>

      <DCSection id="contrast" title="Where it lives in the day" subtitle="Today screen — the card as a slot">
        <DCArtboard id="in-context-today" label="In today's screen" width={phoneSize.width} height={phoneSize.height}>
          <Phone><TodayWithCardSlot /></Phone>
        </DCArtboard>
      </DCSection>
    </DesignCanvas>
  );
}

/* ── Phone shell ────────────────────────────────────────────────── */
function Phone({ children }) {
  return (
    <IOSDevice>
      <div className="page" style={{ background: "var(--paper)", height: "100%", display: "flex", flexDirection: "column", paddingTop: 54 }}>
        {children}
      </div>
    </IOSDevice>
  );
}

/* ════════════════════════════════════════════════════════════════════
   A · EDITORIAL — Plate 18 voice. Headline + prescription line +
   coach quote. Calm. Reads like a magazine.
   ════════════════════════════════════════════════════════════════════ */
function EditorialCard() {
  return (
    <>
      <PlateStrip surface="WORKOUT · TODAY" fig="FIG. 24" right="A · EDITORIAL" />
      <div className="page__body">
        <NavRow back="Today" />

        {/* Headline */}
        <div className="section section--first" style={{ marginTop: 14 }}>
          <Eyebrow coral>WEDNESDAY&nbsp;·&nbsp;MAY 14</Eyebrow>
          <h1 className="h-display" style={{ fontSize: 34, marginTop: 6 }}>{WORKOUT.title}</h1>
          <div style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-2)", letterSpacing: "0.10em", textTransform: "uppercase", marginTop: 6 }}>
            2 mi WU&nbsp;·&nbsp;5 mi at 7:00 / mi&nbsp;·&nbsp;1 mi CD
          </div>
        </div>

        <Hairline style={{ marginTop: 18 }} />

        {/* Coach voice */}
        <Section eyebrow="FROM YOUR COACH" eyebrowCoral>
          <CoachQuote>{COACH_QUOTE}</CoachQuote>
          <div style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-3)", letterSpacing: "0.10em", textTransform: "uppercase", marginTop: 8 }}>
            Why this workout · {WORKOUT.intent}
          </div>
        </Section>

        <div style={{ height: 14 }} />

        {/* Stat strip */}
        <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", padding: "14px 0", borderTop: "1px solid var(--rule)", borderBottom: "1px solid var(--rule)" }}>
          <Strip l="DISTANCE" v="8.0" u="mi" />
          <Strip l="DURATION" v="~64" u="min" border />
          <Strip l="RPE" v="6 / 10" border />
        </div>

        {/* Steps */}
        <Section eyebrow="THE WORKOUT" eyebrowRight={`${WORKOUT.steps.length} STEPS`}>
          <div style={{ marginTop: 4 }}>
            {WORKOUT.steps.map((s, i) => (
              <div className={"step" + (s.quality ? " is-active" : "")} key={i}>
                <span className="step__dot" />
                <div className="step__body">
                  <div className="step__head">
                    <span className="step__name">{s.label}</span>
                    <span className="step__miles">{s.miles.toFixed(1)} mi</span>
                  </div>
                  <div className="step__pace">{s.pace}</div>
                  <div className="step__note">{s.note}</div>
                </div>
              </div>
            ))}
          </div>
        </Section>

        <div style={{ height: 16 }} />

        {/* Prior reference */}
        <Section eyebrow="LAST TIME">
          <p style={{ fontFamily: "var(--font-body)", fontSize: 13, color: "var(--ink)", margin: 0 }}>
            {WORKOUT.prevPrescription}
          </p>
          <p style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13, color: "var(--ink-2)", margin: "4px 0 0 0" }}>
            {WORKOUT.prevCompletion}
          </p>
        </Section>

        <div style={{ height: 24 }} />
      </div>
      <BottomCTA primary="Start workout" secondary="Snooze · Move" />
    </>
  );
}

/* ════════════════════════════════════════════════════════════════════
   B · THE RUN SHEET — verb-first. Big stepped block prescription.
   Reads as a single sheet you could print and tape to the fridge.
   ════════════════════════════════════════════════════════════════════ */
function RunSheetCard() {
  return (
    <>
      <PlateStrip surface="WORKOUT · TODAY" fig="FIG. 24" right="B · RUN SHEET" />
      <div className="page__body" style={{ paddingTop: 14 }}>
        <NavRow back="Today" />

        <div style={{ marginTop: 16 }}>
          <Eyebrow>WED · MAY 14 · WK 9 OF 16</Eyebrow>
          <h1 className="h-display" style={{ fontSize: 28, marginTop: 6 }}>{WORKOUT.title}</h1>
        </div>

        {/* Sheet card */}
        <div style={{ background: "var(--paper-elevated)", border: "1px solid var(--rule)", borderRadius: 12, padding: 16, marginTop: 14 }}>
          {WORKOUT.steps.map((s, i) => (
            <SheetRow key={i} step={s} index={i + 1} last={i === WORKOUT.steps.length - 1} />
          ))}
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", paddingTop: 12, borderTop: "1.5px solid var(--ink)", marginTop: 4 }}>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, letterSpacing: "0.12em", color: "var(--ink)", textTransform: "uppercase", fontWeight: 600 }}>TOTAL</span>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 18, color: "var(--ink)", fontWeight: 600, fontVariantNumeric: "tabular-nums" }}>
              {WORKOUT.totalMiles.toFixed(1)}<span style={{ fontSize: 11, color: "var(--ink-2)", marginLeft: 4 }}>mi</span>
              <span style={{ marginLeft: 12, color: "var(--ink-3)" }}>·</span>
              <span style={{ marginLeft: 12 }}>{WORKOUT.totalMin}<span style={{ fontSize: 11, color: "var(--ink-2)", marginLeft: 4 }}>min</span></span>
            </span>
          </div>
        </div>

        {/* Targets */}
        <Section eyebrow="TARGETS">
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 0, padding: "10px 0", borderTop: "1px solid var(--rule)", borderBottom: "1px solid var(--rule)" }}>
            <Strip l="PACE" v={WORKOUT.paceTarget} u="/ mi" />
            <Strip l="HR" v={WORKOUT.hrTarget} u="bpm · Z3" border />
          </div>
        </Section>

        <CoachQuoteWithLabel quote={COACH_QUOTE} label="FROM YOUR COACH" />

        <div style={{ height: 24 }} />
      </div>
      <BottomCTA primary="Start workout" secondary="Edit · Reschedule" />
    </>
  );
}

function SheetRow({ step, index, last }) {
  return (
    <div style={{ padding: "10px 0", borderBottom: last ? 0 : "1px dashed var(--rule)" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
        <div style={{ display: "flex", alignItems: "baseline", gap: 10 }}>
          <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-3)", fontWeight: 500, letterSpacing: "0.10em" }}>
            {String(index).padStart(2, "0")}
          </span>
          <span style={{ fontFamily: "var(--font-display)", fontSize: 18, fontWeight: 700, color: step.quality ? "var(--coral)" : "var(--ink)" }}>
            {step.label}
          </span>
        </div>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 14, color: "var(--ink)", fontWeight: 600 }}>
          {step.miles.toFixed(1)}<span style={{ fontSize: 10, color: "var(--ink-2)", marginLeft: 4 }}>mi</span>
        </span>
      </div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginTop: 4 }}>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: step.quality ? "var(--coral)" : "var(--ink-2)", letterSpacing: "0.08em", fontWeight: 500 }}>
          {step.pace}
        </span>
        <span style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 12, color: "var(--ink-3)", textAlign: "right", maxWidth: "60%" }}>
          {step.note}
        </span>
      </div>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   C · COCKPIT — big hero numerals, target tiles, profile bar.
   Watch-face energy. For runners who care about hitting the number.
   ════════════════════════════════════════════════════════════════════ */
function CockpitCard() {
  return (
    <>
      <PlateStrip surface="WORKOUT · TODAY" fig="FIG. 24" right="C · COCKPIT" />
      <div className="page__body">
        <NavRow back="Today" />

        <div style={{ marginTop: 12 }}>
          <Eyebrow coral>TODAY · MAY 14 · WED</Eyebrow>
        </div>

        {/* Hero number */}
        <div style={{ marginTop: 10, display: "flex", alignItems: "baseline", gap: 14 }}>
          <span style={{ fontFamily: "var(--font-display)", fontSize: 100, fontWeight: 700, letterSpacing: "-0.03em", lineHeight: 0.9, color: "var(--ink)" }}>
            8
          </span>
          <div>
            <div style={{ fontFamily: "var(--font-mono)", fontSize: 11, letterSpacing: "0.14em", textTransform: "uppercase", color: "var(--ink-2)" }}>MILES</div>
            <div style={{ fontFamily: "var(--font-display)", fontSize: 22, fontWeight: 700, color: "var(--coral)", marginTop: 2 }}>Tempo.</div>
          </div>
        </div>
        <div style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13, color: "var(--ink-2)", marginTop: 8 }}>
          — {WORKOUT.intent}. —
        </div>

        {/* Target tiles */}
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 8, marginTop: 18 }}>
          <Tile label="PACE TARGET" value={WORKOUT.paceTarget} unit="/ mi" />
          <Tile label="HEART RATE" value="152" unit="–162" />
          <Tile label="DURATION" value="~64" unit="min" />
        </div>

        {/* Workout profile — visual bar of step proportions */}
        <Section eyebrow="WORKOUT PROFILE" eyebrowRight="2 + 5 + 1">
          <ProfileBar steps={WORKOUT.steps} total={WORKOUT.totalMiles} />
          <div style={{ display: "flex", justifyContent: "space-between", marginTop: 8 }}>
            {WORKOUT.steps.map((s, i) => (
              <div key={i} style={{ textAlign: i === 0 ? "left" : i === WORKOUT.steps.length - 1 ? "right" : "center", flex: 1 }}>
                <div style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: s.quality ? "var(--coral)" : "var(--ink-2)", letterSpacing: "0.10em", fontWeight: 600 }}>
                  {s.label.toUpperCase()}
                </div>
                <div style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-3)", marginTop: 2 }}>
                  {s.pace}
                </div>
              </div>
            ))}
          </div>
        </Section>

        <div style={{ height: 16 }} />

        <CoachQuoteWithLabel quote={COACH_QUOTE} label="HOW TO RUN IT" />

        <div style={{ height: 24 }} />
      </div>
      <BottomCTA primary="Start" secondary="Sync to watch" />
    </>
  );
}

function Tile({ label, value, unit }) {
  return (
    <div className="stat-tile" style={{ padding: 12, gap: 6 }}>
      <div className="stat-label">{label}</div>
      <div className="stat-value" style={{ fontSize: 22 }}>
        {value}{unit ? <span className="stat-unit" style={{ marginLeft: 4 }}>{unit}</span> : null}
      </div>
    </div>
  );
}

function ProfileBar({ steps, total }) {
  return (
    <div style={{ display: "flex", height: 28, marginTop: 8, borderRadius: 4, overflow: "hidden", border: "1px solid var(--rule)" }}>
      {steps.map((s, i) => {
        const w = (s.miles / total) * 100;
        return (
          <div
            key={i}
            style={{
              flex: `0 0 ${w}%`,
              background: s.quality ? "var(--coral)" : "var(--paper-deep)",
              borderRight: i < steps.length - 1 ? "1px solid var(--rule)" : 0,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              fontFamily: "var(--font-mono)",
              fontSize: 11,
              fontWeight: 600,
              color: s.quality ? "#fff" : "var(--ink)",
              fontVariantNumeric: "tabular-nums",
            }}
          >
            {s.miles}
          </div>
        );
      })}
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   D · BRIEF — one-screen briefing. Big title + one-glance summary.
   For when you trust the plan and just want to go.
   ════════════════════════════════════════════════════════════════════ */
function BriefCard() {
  return (
    <>
      <PlateStrip surface="WORKOUT · TODAY" fig="FIG. 24" right="D · BRIEF" />
      <div className="page__body" style={{ display: "flex", flexDirection: "column" }}>
        <NavRow back="Today" />

        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", paddingTop: 24, paddingBottom: 24 }}>
          <div style={{ textAlign: "center" }}>
            <Eyebrow coral>TODAY</Eyebrow>
            <h1 className="h-display" style={{ fontSize: 40, marginTop: 8 }}>{WORKOUT.title}</h1>
            <div style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 14, color: "var(--ink-2)", marginTop: 10 }}>
              — 2 warm-up · 5 at 7:00 / mi · 1 cool-down. —
            </div>
          </div>

          <div style={{ height: 28 }} />

          {/* one-line stat row */}
          <div style={{ display: "flex", justifyContent: "center", gap: 32, padding: "16px 0", borderTop: "1px solid var(--rule)", borderBottom: "1px solid var(--rule)" }}>
            <BriefStat l="DIST" v="8" u="mi" />
            <BriefStat l="TIME" v="64" u="min" />
            <BriefStat l="PACE" v="7:00" u="/mi" />
          </div>

          <div style={{ height: 26 }} />

          <CoachQuote>{COACH_QUOTE}</CoachQuote>

          <div style={{ height: 16 }} />
          <p style={{ fontFamily: "var(--font-mono)", fontSize: 9, letterSpacing: "0.10em", color: "var(--ink-3)", textTransform: "uppercase", textAlign: "center", margin: 0 }}>
            Tap to see the full plan
          </p>
        </div>
      </div>
      <BottomCTA primary="Start workout" />
    </>
  );
}

function BriefStat({ l, v, u }) {
  return (
    <div style={{ textAlign: "center" }}>
      <div style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-2)", letterSpacing: "0.12em", textTransform: "uppercase" }}>{l}</div>
      <div style={{ fontFamily: "var(--font-mono)", fontWeight: 600, fontSize: 24, color: "var(--ink)", marginTop: 3 }}>
        {v}<span style={{ fontSize: 10, color: "var(--ink-2)", marginLeft: 3 }}>{u}</span>
      </div>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   CONTEXT — Today screen with a placeholder showing where the card
   would slot in.
   ════════════════════════════════════════════════════════════════════ */
function TodayWithCardSlot() {
  return (
    <>
      <PlateStrip surface="LOG · v1 DIARY + CHARTS" fig="FIG. 18" right="MAY 14 · 2026" />
      <div className="page__body">
        <div className="section section--first">
          <Eyebrow coral>WEDNESDAY</Eyebrow>
          <h1 className="h-display" style={{ fontSize: 34 }}>May 14th.</h1>
          <div style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13, color: "var(--ink-3)" }}>
            — seven weeks to Boston. —
          </div>
        </div>

        <div style={{ height: 18 }} />
        <EditorialRule />

        {/* The slot — a tappable card preview */}
        <Section eyebrow="TODAY · YOUR WORKOUT" eyebrowRight="TAP TO OPEN ↗">
          <div style={{
            background: "var(--card)",
            border: "1px solid var(--rule)",
            borderRadius: 12,
            padding: 16,
            marginTop: 6,
            boxShadow: "0 2px 8px rgba(0,0,0,0.04)",
          }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
              <div>
                <h3 style={{ fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 22, color: "var(--ink)", margin: 0 }}>
                  {WORKOUT.title}
                </h3>
                <div style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-2)", letterSpacing: "0.10em", textTransform: "uppercase", marginTop: 4 }}>
                  2 mi WU · 5 at 7:00 / mi · 1 mi CD
                </div>
              </div>
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--coral)", letterSpacing: "0.12em", textTransform: "uppercase", fontWeight: 600 }}>
                ↗
              </span>
            </div>

            {/* mini profile */}
            <div style={{ marginTop: 12 }}>
              <ProfileBar steps={WORKOUT.steps} total={WORKOUT.totalMiles} />
            </div>

            <div style={{ display: "flex", justifyContent: "space-between", marginTop: 10 }}>
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-2)", letterSpacing: "0.10em", textTransform: "uppercase" }}>
                8 MI · ~64 MIN
              </span>
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--coral)", letterSpacing: "0.10em", textTransform: "uppercase", fontWeight: 600 }}>
                START ↗
              </span>
            </div>
          </div>
        </Section>

        <div style={{ height: 20 }} />
        <EditorialRule />

        <Section eyebrow="FROM YOUR COACH" eyebrowCoral>
          <CoachQuote>{COACH_QUOTE}</CoachQuote>
        </Section>

        <div style={{ height: 24 }} />
      </div>
    </>
  );
}

/* ════════════════════════════════════════════════════════════════════
   Small shared pieces
   ════════════════════════════════════════════════════════════════════ */
function NavRow({ back }) {
  return (
    <div style={{ display: "flex", justifyContent: "space-between", paddingTop: 0 }}>
      <a className="link" style={{ fontSize: 13 }}>← {back}</a>
      <a className="link" style={{ fontSize: 13 }}>Edit</a>
    </div>
  );
}

function Strip({ l, v, u, border }) {
  return (
    <div style={{ borderLeft: border ? "1px solid var(--rule)" : "0", display: "flex", flexDirection: "column", gap: 4, paddingLeft: border ? 14 : 0, paddingRight: 14 }}>
      <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-2)", letterSpacing: "0.10em", textTransform: "uppercase" }}>{l}</span>
      <span style={{ fontFamily: "var(--font-mono)", fontWeight: 600, fontSize: 20, color: "var(--ink)", fontVariantNumeric: "tabular-nums" }}>
        {v}
        {u ? <span style={{ fontSize: 10, color: "var(--ink-2)", marginLeft: 4 }}>{u}</span> : null}
      </span>
    </div>
  );
}

function CoachQuoteWithLabel({ quote, label }) {
  return (
    <Section eyebrow={label} eyebrowCoral>
      <CoachQuote>{quote}</CoachQuote>
    </Section>
  );
}

function BottomCTA({ primary, secondary }) {
  return (
    <div style={{
      flexShrink: 0,
      padding: "12px 24px 16px 24px",
      borderTop: "1px solid var(--rule)",
      background: "var(--paper)",
      display: "flex",
      flexDirection: "column",
      gap: 8,
    }}>
      <button className="btn btn--primary">{primary} ↗</button>
      {secondary ? (
        <button style={{
          background: "transparent",
          border: 0,
          fontFamily: "var(--font-mono)",
          fontSize: 10,
          letterSpacing: "0.12em",
          textTransform: "uppercase",
          color: "var(--ink-2)",
          padding: "6px 0 0 0",
          cursor: "pointer",
        }}>
          {secondary}
        </button>
      ) : null}
    </div>
  );
}

/* ── mount ──────────────────────────────────────────────────────── */
const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(<App />);

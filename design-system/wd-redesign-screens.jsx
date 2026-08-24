/* global React, wdStore, WK, WX, REP_PLAN, HR_ZONES, STREAM, TIZ, COMPARE, RECENT_AVG, fmtClock, fmtPaceVal, paceUnit, distVal, distUnit, elevVal, elevUnit, wd, RepChart, HRZoneTimeline, PaceTrace, CadenceStrip, ElevGradeProfile, RepRecovery, TimeInZoneBar, RepTable, ComparisonChart, DeltaChips, RouteMap */
/* ════════════════════════════════════════════════════════════════════
   WORKOUT DETAIL · REDESIGN — THREE DIRECTIONS
   A · Rep Receipt  ·  B · Telemetry Dashboard  ·  C · The Session Read
   ════════════════════════════════════════════════════════════════════ */

const COR = "var(--coral)";
const INK = "var(--ink)";
const INK2 = "var(--ink-2)";
const INK3 = "var(--ink-3)";
const RULE = "var(--rule)";

/* ─── shared chrome ──────────────────────────────────────────────────── */
function Plate({ surface, right }) {
  return (
    <div style={{ display: "flex", justifyContent: "space-between", padding: "14px 22px 0" }}>
      <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
        <span style={{ ...wd.eyebrow, color: INK }}>RUNNING LOG</span>
        <span style={wd.eyebrow}>— {surface}</span>
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 2, textAlign: "right" }}>
        <span style={{ ...wd.eyebrow, color: INK }}>{WK.source.toUpperCase()}</span>
        <span style={wd.eyebrow}>{right}</span>
      </div>
    </div>
  );
}

function TypePill() {
  return (
    <span style={{
      display: "inline-flex", alignItems: "center", gap: 5,
      fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 600, letterSpacing: "0.12em",
      color: COR, background: "var(--coral-wash)", padding: "5px 11px", borderRadius: 999,
    }}>{WK.type} <span style={{ opacity: 0.6 }}>▾</span></span>
  );
}

function SecHead({ children, value, sub }) {
  return (
    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
      <span style={wd.eyebrow}>{children}</span>
      {value != null && (
        <span style={{ ...wd.mono, fontSize: 11, color: INK2 }}>
          {value}{sub && <span style={{ color: INK3, marginLeft: 6 }}>{sub}</span>}
        </span>
      )}
    </div>
  );
}

/* weather woven into a sentence — adapts to the weather-adjust tweak */
function WeatherSentence() {
  const st = wdStore.use();
  return (
    <p style={{ ...wd.italic, fontSize: 14, color: INK, margin: 0, lineHeight: 1.62 }}>
      Run in <span style={{ fontStyle: "normal", fontWeight: 700 }}>{WX.tempF}°F</span> with a{" "}
      <span style={{ color: COR, fontStyle: "normal", fontWeight: 600 }}>{WX.dewPointF}° dew point</span>{" "}
      — sticky, {WX.heatCategory.toLowerCase()} heat that quietly taxes a threshold effort.{" "}
      {st.weatherAdjust
        ? <>Paces below are <span style={{ fontStyle: "normal", fontWeight: 600 }}>heat-adjusted +{WX.adjustSecPerMi}s{paceUnit(st.units)}</span>, so the {fmtPaceVal(WK.avgWorkPaceSec, st.units, true)} work average is really worth about {fmtPaceVal(WK.avgWorkPaceSec, st.units, false)} on a cool day.</>
        : <>Adjusted for the air, your {fmtPaceVal(WK.avgWorkPaceSec, st.units, false)} average is worth roughly <span style={{ color: COR, fontStyle: "normal", fontWeight: 600 }}>{fmtPaceVal(WK.avgWorkPaceSec - WX.adjustSecPerMi, st.units, false)}</span> in cool conditions.</>}
    </p>
  );
}

/* shell */
function Screen({ surface, right, children }) {
  return (
    <div style={{ height: "100%", background: "var(--paper)", display: "flex", flexDirection: "column", overflow: "hidden" }}>
      <Plate surface={surface} right={right} />
      <div style={{ flex: 1, overflowY: "auto", padding: "8px 0 28px" }}>{children}</div>
    </div>
  );
}

const sx = { pad: "22px 22px 0" };

/* ════════════════════════════════════════════════════════════════════
   A · REP RECEIPT — hero rep chart, then the receipt of telemetry
   ════════════════════════════════════════════════════════════════════ */
function DirReceipt() {
  const st = wdStore.use();
  return (
    <Screen surface="WORKOUT · DETAIL" right={`THU · ${WK.time}`}>
      {/* heading */}
      <div style={{ padding: "16px 22px 0" }}>
        <TypePill />
        <h1 style={{ fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 34, margin: "12px 0 0", letterSpacing: "-0.01em", color: INK, lineHeight: 1 }}>{WK.title}</h1>
        <p style={{ ...wd.italic, fontSize: 13, color: INK3, margin: "8px 0 0" }}>— {WK.prescription} · {WK.fullDate} —</p>
      </div>

      {/* hero rep chart */}
      <div style={{ padding: "16px 22px 0" }}>
        <SecHead value={`${REP_PLAN.length} REPS`} sub="WORK">REP BY REP</SecHead>
        <RepChart height={236} />
      </div>

      {/* stat strip */}
      <div style={{ margin: "16px 22px 0", display: "grid", gridTemplateColumns: "repeat(4,1fr)", borderTop: `1px solid ${RULE}`, borderBottom: `1px solid ${RULE}` }}>
        {[
          { l: "AVG WORK", v: fmtPaceVal(WK.avgWorkPaceSec, st.units, st.weatherAdjust), u: paceUnit(st.units) },
          { l: "WORK", v: distVal(WK.workDistMi, st.units).toFixed(1), u: distUnit(st.units) },
          { l: "AVG HR", v: String(WK.avgHr), u: "bpm" },
          { l: "SPREAD", v: String(WK.spreadSec), u: "s" },
        ].map((s, i, a) => (
          <div key={s.l} style={{ padding: "12px 4px", display: "flex", flexDirection: "column", alignItems: "center", gap: 4, borderRight: i < a.length - 1 ? `1px solid ${RULE}` : "none" }}>
            <span style={wd.eyebrowSm}>{s.l}</span>
            <span style={{ ...wd.mono, fontSize: 16, fontWeight: 600, color: i === 0 ? COR : INK }}>{s.v}<span style={{ fontSize: 9, color: INK3, marginLeft: 2 }}>{s.u}</span></span>
          </div>
        ))}
      </div>

      {/* analysis + weather */}
      <div style={{ padding: "20px 22px 0" }}>
        <SecHead>THE READ</SecHead>
        <div style={{ marginTop: 8 }}><WeatherSentence /></div>
        <p style={{ ...wd.italic, fontSize: 14, color: INK, margin: "10px 0 0", lineHeight: 1.62 }}>
          Six reps inside an <span style={{ fontStyle: "normal", fontWeight: 600 }}>{WK.spreadSec}-second</span> spread, HR pinned to threshold from rep two on. Controlled and even — exactly the session you drew up.
        </p>
      </div>

      {/* time in zone */}
      <div style={sx}><SecHead value="Z4" sub="DOMINANT">TIME IN HR ZONE</SecHead><TimeInZoneBar /></div>

      {/* HR timeline */}
      <div style={sx}><SecHead value={WK.avgHr} sub={`${WK.maxHr} MAX`}>HEART RATE · FULL SESSION</SecHead><HRZoneTimeline /></div>

      {/* pace trace */}
      <div style={sx}><SecHead value={fmtPaceVal(WK.avgWorkPaceSec, st.units, st.weatherAdjust)} sub={`WORK ${paceUnit(st.units)}`}>PACE</SecHead><PaceTrace /></div>

      {/* cadence */}
      <div style={sx}><SecHead value={WK.avgCadence} sub="SPM">CADENCE</SecHead><CadenceStrip /></div>

      {/* elevation */}
      <div style={sx}><SecHead value={`+${elevVal(WK.elevGainFt, st.units)}`} sub={`${elevUnit(st.units)} GAIN`}>ELEVATION · GRADE</SecHead><ElevGradeProfile /></div>

      {/* rep recovery */}
      <div style={sx}><SecHead>HR RECOVERY · AFTER EACH REP</SecHead><RepRecovery /></div>

      {/* rep table */}
      <div style={sx}>
        <SecHead value={fmtPaceVal(Math.min(...REP_PLAN.map(r=>r.paceSec)), st.units, st.weatherAdjust)} sub="FASTEST REP">SPLITS · VS TARGET</SecHead>
        <div style={{ marginTop: 6 }}><RepTable /></div>
      </div>

      {/* comparison */}
      <div style={sx}>
        <SecHead value={COMPARE[st.comparison].label}>VS SIMILAR</SecHead>
        <ComparisonChart />
        <DeltaChips />
      </div>

      {/* route */}
      <div style={sx}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginBottom: 8 }}>
          <span style={wd.eyebrow}>ROUTE</span>
          <span style={{ ...wd.eyebrow, color: COR, cursor: "pointer" }}>FULL MAP ↗</span>
        </div>
        <RouteMap />
      </div>
    </Screen>
  );
}

/* ════════════════════════════════════════════════════════════════════
   B · TELEMETRY DASHBOARD — densest, everything synchronized
   ════════════════════════════════════════════════════════════════════ */
function StatCell({ l, v, u, accent }) {
  return (
    <div style={{ padding: "10px 12px", borderRight: `1px solid ${RULE}`, borderBottom: `1px solid ${RULE}` }}>
      <span style={{ ...wd.eyebrowSm }}>{l}</span>
      <div style={{ ...wd.mono, fontSize: 18, fontWeight: 600, color: accent ? COR : INK, marginTop: 3, lineHeight: 1 }}>
        {v}{u && <span style={{ fontSize: 9, color: INK3, marginLeft: 2 }}>{u}</span>}
      </div>
    </div>
  );
}

function DirDashboard() {
  const st = wdStore.use();
  return (
    <Screen surface="WORKOUT · TELEMETRY" right={`THU 05.21 · ${WK.time}`}>
      {/* compact heading */}
      <div style={{ padding: "14px 22px 0", display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
        <div>
          <TypePill />
          <h1 style={{ fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 23, margin: "10px 0 0", letterSpacing: "-0.01em", color: INK, lineHeight: 1 }}>{WK.title}</h1>
        </div>
        <span style={{ ...wd.eyebrowSm, textAlign: "right", maxWidth: 96 }}>{WK.prescription}</span>
      </div>

      {/* big stat grid */}
      <div style={{ margin: "14px 22px 0", border: `1px solid ${RULE}`, borderRight: "none", borderBottom: "none", display: "grid", gridTemplateColumns: "repeat(3,1fr)" }}>
        <StatCell l="WORK DIST" v={distVal(WK.workDistMi, st.units).toFixed(2)} u={distUnit(st.units)} />
        <StatCell l="WORK TIME" v={WK.workTime} />
        <StatCell l="AVG WORK" v={fmtPaceVal(WK.avgWorkPaceSec, st.units, st.weatherAdjust)} u={paceUnit(st.units)} accent />
        <StatCell l="AVG HR" v={WK.avgHr} u="bpm" />
        <StatCell l="MAX HR" v={WK.maxHr} u="bpm" />
        <StatCell l="SPREAD" v={WK.spreadSec} u="s" />
        <StatCell l="AVG POWER" v={WK.avgPowerW} u="w" />
        <StatCell l="CADENCE" v={WK.avgCadence} u="spm" />
        <StatCell l="ELEV" v={`+${elevVal(WK.elevGainFt, st.units)}`} u={elevUnit(st.units)} />
      </div>

      {/* weather context line */}
      <div style={{ padding: "16px 22px 0" }}>
        <SecHead>CONDITIONS</SecHead>
        <div style={{ marginTop: 7 }}><WeatherSentence /></div>
      </div>

      {/* hero rep chart */}
      <div style={sx}><SecHead value={`${REP_PLAN.length} REPS`}>REP BY REP</SecHead><RepChart height={224} /></div>

      {/* synchronized stack */}
      <div style={{ padding: "20px 22px 0" }}>
        <SecHead value="00:00" sub={`→ ${WK.totalTime}`}>SYNCHRONIZED · HR / PACE / CADENCE / ELEV</SecHead>
        <div style={{ marginTop: 8, border: `1px solid ${RULE}` }}>
          <div style={{ padding: "6px 4px 0" }}><HRZoneTimeline height={132} /></div>
          <div style={{ borderTop: `1px solid ${RULE}`, padding: "6px 4px 0" }}><PaceTrace height={96} /></div>
          <div style={{ borderTop: `1px solid ${RULE}`, padding: "6px 4px 0" }}><CadenceStrip height={62} /></div>
          <div style={{ borderTop: `1px solid ${RULE}`, padding: "6px 4px 2px" }}><ElevGradeProfile height={74} /></div>
        </div>
        <p style={{ ...wd.italic, fontSize: 11, color: INK3, margin: "6px 0 0" }}>— shared time axis · coral bands = work reps —</p>
      </div>

      {/* time in zone */}
      <div style={sx}><SecHead value={fmtClock(TIZ.Z4)} sub="IN Z4">TIME IN HR ZONE</SecHead><TimeInZoneBar /></div>

      {/* rep recovery */}
      <div style={sx}><SecHead>HR RECOVERY · PER REP</SecHead><RepRecovery /></div>

      {/* full rep table */}
      <div style={sx}><SecHead value={fmtPaceVal(Math.min(...REP_PLAN.map(r=>r.paceSec)), st.units, st.weatherAdjust)} sub="FASTEST">REPS</SecHead><div style={{ marginTop: 6 }}><RepTable /></div></div>

      {/* comparison */}
      <div style={sx}>
        <SecHead value={COMPARE[st.comparison].label}>VS SIMILAR SESSIONS</SecHead>
        <ComparisonChart />
        <DeltaChips />
      </div>

      {/* route */}
      <div style={sx}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginBottom: 8 }}>
          <span style={wd.eyebrow}>ROUTE · {WK.place.split("·")[1]}</span>
          <span style={{ ...wd.eyebrow, color: COR, cursor: "pointer" }}>OPEN ↗</span>
        </div>
        <RouteMap />
      </div>
    </Screen>
  );
}

/* ════════════════════════════════════════════════════════════════════
   C · THE SESSION READ — narrative-forward, charts as evidence
   ════════════════════════════════════════════════════════════════════ */
function DirRead() {
  const st = wdStore.use();
  const fastest = Math.min(...REP_PLAN.map((r) => r.paceSec));
  return (
    <Screen surface="WORKOUT · THE READ" right="THU 05.21">
      {/* editorial heading */}
      <div style={{ padding: "24px 22px 0" }}>
        <span style={wd.eyebrow}>THE THURSDAY THRESHOLD</span>
        <h1 style={{ fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 34, margin: "10px 0 0", letterSpacing: "-0.01em", color: INK, lineHeight: 1.08 }}>
          Six reps, {WK.spreadSec} seconds apart,<br /><span style={{ color: COR }}>held in the heat.</span>
        </h1>
      </div>

      {/* lede with weather woven in */}
      <div style={{ padding: "16px 22px 0" }}><WeatherSentence /></div>

      {/* 3 hero stats */}
      <div style={{ margin: "20px 22px 0", display: "grid", gridTemplateColumns: "repeat(3,1fr)", borderTop: `1px solid ${RULE}`, borderBottom: `1px solid ${RULE}` }}>
        {[
          { l: "WORK", v: distVal(WK.workDistMi, st.units).toFixed(1), u: distUnit(st.units) },
          { l: "AVG WORK", v: fmtPaceVal(WK.avgWorkPaceSec, st.units, st.weatherAdjust), u: paceUnit(st.units), accent: true },
          { l: "AVG HR", v: String(WK.avgHr), u: "bpm" },
        ].map((s, i, a) => (
          <div key={s.l} style={{ padding: "16px 4px", display: "flex", flexDirection: "column", alignItems: "center", gap: 4, borderRight: i < a.length - 1 ? `1px solid ${RULE}` : "none" }}>
            <span style={wd.eyebrowSm}>{s.l}</span>
            <span style={{ ...wd.mono, fontSize: 24, fontWeight: 600, color: s.accent ? COR : INK, lineHeight: 1 }}>{s.v}<span style={{ fontSize: 10, color: INK3, marginLeft: 3 }}>{s.u}</span></span>
          </div>
        ))}
      </div>

      {/* the rep chart as evidence */}
      <div style={{ padding: "22px 22px 0" }}>
        <SecHead>EVERY REP</SecHead>
        <p style={{ ...wd.italic, fontSize: 12, color: INK3, margin: "4px 0 0" }}>— taller = faster · line is avg HR · widths to distance —</p>
        <RepChart height={232} />
      </div>

      {/* narrative callout — fastest/slowest */}
      <div style={{ margin: "18px 22px 0", padding: "16px 0", borderTop: `1px solid ${RULE}`, borderBottom: `1px solid ${RULE}`, display: "grid", gridTemplateColumns: "1fr 1fr" }}>
        <div style={{ borderRight: `1px solid ${RULE}`, paddingRight: 16 }}>
          <span style={wd.eyebrowSm}>SHARPEST REP · 5</span>
          <div style={{ ...wd.mono, fontSize: 26, fontWeight: 600, color: COR, marginTop: 4, lineHeight: 1 }}>{fmtPaceVal(fastest, st.units, st.weatherAdjust)}</div>
          <span style={{ ...wd.italic, fontSize: 12, color: INK3 }}>last hard 1k, still climbing</span>
        </div>
        <div style={{ paddingLeft: 16 }}>
          <span style={wd.eyebrowSm}>EVENNESS</span>
          <div style={{ ...wd.mono, fontSize: 26, fontWeight: 600, color: INK, marginTop: 4, lineHeight: 1 }}>{WK.spreadSec}s</div>
          <span style={{ ...wd.italic, fontSize: 12, color: INK3 }}>rep-to-rep spread</span>
        </div>
      </div>

      {/* HR story */}
      <div style={{ padding: "22px 22px 0" }}>
        <SecHead>HEART RATE NEVER RAN AWAY</SecHead>
        <p style={{ ...wd.italic, fontSize: 12, color: INK3, margin: "4px 0 0" }}>— pinned to the Z4 band, recovering between each. —</p>
        <HRZoneTimeline />
      </div>

      {/* recovery */}
      <div style={sx}>
        <SecHead>AND IT KEPT DROPPING IN THE RESTS</SecHead>
        <RepRecovery />
      </div>

      {/* time in zone */}
      <div style={sx}><SecHead value="Z4" sub="WHERE YOU LIVED">THE SHAPE OF THE EFFORT</SecHead><TimeInZoneBar /></div>

      {/* splits */}
      <div style={sx}><SecHead>THE NUMBERS</SecHead><div style={{ marginTop: 6 }}><RepTable /></div></div>

      {/* comparison story */}
      <div style={sx}>
        <SecHead value={COMPARE[st.comparison].label}>WHERE THIS SITS</SecHead>
        <p style={{ ...wd.italic, fontSize: 12, color: INK3, margin: "4px 0 0" }}>— your fastest threshold average yet, on the worst air. —</p>
        <ComparisonChart />
      </div>

      {/* route */}
      <div style={sx}><span style={wd.eyebrow}>WHERE</span><div style={{ marginTop: 8 }}><RouteMap height={130} /></div></div>
    </Screen>
  );
}

Object.assign(window, { DirReceipt, DirDashboard, DirRead });

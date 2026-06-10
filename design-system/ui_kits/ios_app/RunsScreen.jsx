// Post Run Drip · iOS UI kit · Runs screen (history)
//
// Mirrors HistoryView.swift — overview stats header, then a filterable
// list of all runs as JournalLogRow-style entries. Tapping a row opens
// the workout detail (or history detail sheet, conceptually).

const RUNS_CSS = `
.prd-runs__filter {
  display: flex; gap: 0; overflow-x: auto;
  border-bottom: 1px solid var(--rule);
  scrollbar-width: none;
}
.prd-runs__filter::-webkit-scrollbar { display: none; }
.prd-runs__filter-btn {
  flex: 0 0 auto;
  padding: 12px 16px;
  background: transparent; border: 0;
  font-family: var(--font-mono);
  font-size: 10px; font-weight: 500;
  letter-spacing: 0.12em; color: var(--ink-2);
  text-transform: uppercase;
  cursor: pointer;
  position: relative;
}
.prd-runs__filter-btn.is-active { color: var(--coral); }
.prd-runs__filter-btn.is-active::after {
  content: ""; position: absolute; left: 16px; right: 16px; bottom: 0;
  height: 1.5px; background: var(--coral);
}

.prd-runs__row {
  display: grid;
  grid-template-columns: 2px 1fr;
  gap: 14px;
  padding: 18px 24px;
  border-bottom: 1px solid var(--rule);
  cursor: pointer;
}
.prd-runs__row:hover { background: rgba(0,0,0,0.015); }
.prd-runs__row-rail { border-radius: 1px; margin: 4px 0; }
.prd-runs__row-date {
  font-family: var(--font-mono);
  font-size: 10px; font-weight: 500;
  letter-spacing: 0.10em; color: var(--ink-2);
  text-transform: uppercase;
}
.prd-runs__row-type {
  font-family: var(--font-mono);
  font-size: 10px; font-weight: 500;
  letter-spacing: 0.10em; color: var(--ink-2);
  text-transform: uppercase;
}
.prd-runs__row-headline {
  font-family: var(--font-display);
  font-size: 22px; font-weight: 700;
  color: var(--ink); letter-spacing: -0.01em;
  font-variant-numeric: tabular-nums;
  margin-top: 4px;
}
.prd-runs__row-meta {
  font-family: var(--font-mono);
  font-size: 10px; font-weight: 500;
  letter-spacing: 0.08em; color: var(--ink-3);
  margin-top: 4px;
  text-transform: uppercase;
  font-variant-numeric: tabular-nums;
}
.prd-runs__row-mood {
  font-family: var(--font-mono);
  font-size: 10px; font-weight: 500;
  letter-spacing: 0.10em;
  margin-top: 8px;
  text-transform: uppercase;
}
.prd-runs__month-header {
  font-family: var(--font-mono);
  font-size: 10px; font-weight: 500;
  letter-spacing: 0.14em; color: var(--ink-3);
  text-transform: uppercase;
  padding: 20px 24px 8px 24px;
  background: var(--paper);
}
`;

const RUNS = [
  { id: "r1",  date: "MAY 7",  day: "Friday",    type: "EASY",      dist: "5.01 MI", time: "35:55", pace: "7:11", mood: "positive",   month: "MAY" },
  { id: "r2",  date: "MAY 5",  day: "Tuesday",   type: "TEMPO",     dist: "11.0 MI", time: "1:09:18", pace: "6:18", mood: "positive",   month: "MAY" },
  { id: "r3",  date: "MAY 3",  day: "Sunday",    type: "LONG RUN",  dist: "18.0 MI", time: "2:15:36", pace: "7:32", mood: "tired",      month: "MAY" },
  { id: "r4",  date: "MAY 2",  day: "Saturday",  type: "RECOVERY",  dist: "4.0 MI",  time: "32:56", pace: "8:14", mood: "neutral",    month: "MAY" },
  { id: "r5",  date: "APR 30", day: "Thursday",  type: "INTERVALS", dist: "8.6 MI",  time: "57:35", pace: "6:42", mood: "positive",   month: "APR" },
  { id: "r6",  date: "APR 28", day: "Tuesday",   type: "EASY",      dist: "6.0 MI",  time: "45:48", pace: "7:38", mood: "neutral",    month: "APR" },
  { id: "r7",  date: "APR 26", day: "Sunday",    type: "LONG RUN",  dist: "20.0 MI", time: "2:33:20", pace: "7:40", mood: "struggling", month: "APR" },
  { id: "r8",  date: "APR 24", day: "Friday",    type: "RECOVERY",  dist: "4.0 MI",  time: "33:24", pace: "8:21", mood: "tired",      month: "APR" },
  { id: "r9",  date: "APR 23", day: "Thursday",  type: "TEMPO",     dist: "9.5 MI",  time: "1:00:18", pace: "6:21", mood: "energized",  month: "APR" },
  { id: "r10", date: "APR 21", day: "Tuesday",   type: "EASY",      dist: "7.0 MI",  time: "53:48", pace: "7:41", mood: "positive",   month: "APR" },
];

const FILTERS = ["ALL", "EASY", "TEMPO", "INTERVALS", "LONG RUN", "RECOVERY"];

const RunsScreen = ({ onOpenWorkout, onOpenEntry, onAddManual, onClose }) => {
  const [filter, setFilter] = React.useState("ALL");
  const visible = filter === "ALL" ? RUNS : RUNS.filter(r => r.type === filter);

  // Group by month for headers
  const months = [];
  const byMonth = {};
  visible.forEach(r => {
    if (!byMonth[r.month]) { byMonth[r.month] = []; months.push(r.month); }
    byMonth[r.month].push(r);
  });

  const totalMiles = visible.reduce((s, r) => s + parseFloat(r.dist), 0).toFixed(1);
  const moodCount = visible.reduce((acc, r) => { acc[r.mood] = (acc[r.mood] || 0) + 1; return acc; }, {});
  const dominantMood = Object.keys(moodCount).sort((a, b) => moodCount[b] - moodCount[a])[0] || "—";

  return (
    <div className="page">
      <style>{RUNS_CSS}</style>
      <PlateStrip surface="HISTORY · ALL RUNS" fig="FIG. 19" />

      <div className="page__body" style={{ padding: 0 }}>
        {/* Sheet chrome — only when opened as a sheet */}
        {onClose && (
          <div style={{ display: "flex", justifyContent: "space-between", padding: "0 24px 0 24px" }}>
            <a className="link" onClick={onClose} style={{ fontSize: 13 }}>Back</a>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, letterSpacing: "0.12em", color: "var(--ink-3)", textTransform: "uppercase" }}>HISTORY · INDEX</span>
          </div>
        )}

        {/* Header */}
        <div style={{ padding: "16px 24px 0 24px", display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
          <div>
            <Eyebrow coral>HISTORY</Eyebrow>
            <h1 className="h-display" style={{ fontSize: 30, marginTop: 4 }}>Every run, indexed.</h1>
            <div style={{
              fontFamily: "var(--font-body)", fontStyle: "italic",
              fontSize: 13, color: "var(--ink-3)", marginTop: 4,
            }}>
              — {visible.length} entries · {totalMiles} mi total · top mood {dominantMood}. —
            </div>
          </div>
          <span
            onClick={onAddManual}
            style={{
              fontFamily: "var(--font-mono)", fontSize: 11, fontWeight: 500,
              letterSpacing: "0.14em", color: "var(--coral)",
              cursor: "pointer", textTransform: "uppercase",
              padding: "8px 0 0 0", whiteSpace: "nowrap",
            }}
          >
            + ADD ↗
          </span>
        </div>

        {/* Filter bar */}
        <div style={{ marginTop: 14 }} />
        <div className="prd-runs__filter">
          {FILTERS.map(f => (
            <button
              key={f}
              className={"prd-runs__filter-btn" + (filter === f ? " is-active" : "")}
              onClick={() => setFilter(f)}
            >
              {f}{f === "ALL" ? "" : ""}
            </button>
          ))}
        </div>

        {/* List grouped by month */}
        {months.map((m, mi) => (
          <React.Fragment key={m}>
            <div className="prd-runs__month-header">{m} 2026  ·  {byMonth[m].length} {byMonth[m].length === 1 ? "RUN" : "RUNS"}</div>
            {byMonth[m].map((r, i) => {
              const moodCfg = MOOD_COLORS[r.mood] || { c: "var(--ink-3)" };
              return (
                <div
                  key={r.id}
                  className="prd-runs__row"
                  onClick={() => onOpenEntry && onOpenEntry(r)}
                >
                  <div className="prd-runs__row-rail" style={{ background: moodCfg.c }} />
                  <div>
                    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
                      <span className="prd-runs__row-date">{r.day.toUpperCase()} · {r.date}</span>
                      <span className="prd-runs__row-type">{r.type}</span>
                    </div>
                    <div className="prd-runs__row-headline">{r.dist}</div>
                    <div className="prd-runs__row-meta">
                      {r.time}  ·  {r.pace} / MI
                    </div>
                    <div className="prd-runs__row-mood" style={{ color: moodCfg.c }}>
                      {r.mood.toUpperCase()}
                    </div>
                  </div>
                </div>
              );
            })}
          </React.Fragment>
        ))}

        <div style={{ height: 40 }} />
      </div>
    </div>
  );
};

window.RunsScreen = RunsScreen;

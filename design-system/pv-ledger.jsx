/* global React, window */
/* ============================================================
   DIRECTION B · ZONE LEDGER (the data-centric one)
   A 100% stacked distribution bar + a per-zone ledger:
   miles, share, pace range, and a faster/slower trend per zone.
   Answers all four questions at a glance. Tap a row or segment
   to isolate a zone.
   ============================================================ */
(function () {
  "use strict";
  const { useState, useMemo } = React;
  const PV = window.PV;

  // per-zone pace trend: early block (wk1–4) vs late (wk6–9)
  function ledgerTrend() {
    const map = {};
    PV.ZONES.forEach((z) => (map[z.id] = { early: [], late: [] }));
    PV.WORKOUTS.forEach((w) => {
      const z = PV.zoneOf(w.paceSeconds);
      if (w.week <= 4) map[z.id].early.push(w);
      else if (w.week >= 6) map[z.id].late.push(w);
    });
    const wavg = (arr) => arr.length ? arr.reduce((s, w) => s + w.paceSeconds * w.miles, 0) / arr.reduce((s, w) => s + w.miles, 0) : null;
    const out = {};
    PV.ZONES.forEach((z) => {
      const e = wavg(map[z.id].early), l = wavg(map[z.id].late);
      out[z.id] = (e != null && l != null) ? Math.round(e - l) : null; // +ve = faster
    });
    return out;
  }

  function paceRange(zone, scaleSlow, scaleFast) {
    const hi = Math.min(zone.hi, 700), lo = Math.max(zone.lo, 300);
    if (zone.id === "rec") return PV.fmtPace(lo) + "+";
    if (zone.id === "vo2") return "≤ " + PV.fmtPace(hi);
    return PV.fmtPace(hi) + "–" + PV.fmtPace(lo);
  }

  function LedgerBody({ mode }) {
    const [sel, setSel] = useState(null);

    const agg = useMemo(() => PV.aggregate(PV.WORKOUTS), []);
    const trend = useMemo(ledgerTrend, []);

    const rows = useMemo(() => {
      let rs = agg.rows.filter((r) => r.miles > 0);
      if (mode === "workouts") {
        rs = rs.filter((r) => PV.QUALITY_IDS.includes(r.zone.id));
        const tot = rs.reduce((s, r) => s + r.miles, 0) || 1;
        rs = rs.map((r) => ({ ...r, pct: (r.miles / tot) * 100 }));
      }
      return rs.slice().reverse(); // fastest at top — reads like a leaderboard of intensity? keep slow→fast
    }, [agg, mode]);
    const ordered = rows.slice().reverse(); // slow→fast top to bottom

    const totalMiles = mode === "workouts" ? agg.qualityMiles : agg.total;
    const aerobicPct = 100 - agg.qualityPct;

    return (
      <React.Fragment>
        {/* stacked distribution bar */}
        <div style={{ padding: "10px 22px 0" }}>
          <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between", marginBottom: 8 }}>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 9.5, color: "var(--ink-2)", letterSpacing: ".5px" }}>
              {mode === "workouts" ? "SHARE OF QUALITY MILES" : "SHARE OF ALL MILES"}
            </span>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, fontWeight: 600, color: "var(--ink)" }}>
              {Math.round(totalMiles)} <span style={{ color: "var(--ink-2)", fontWeight: 400, fontSize: 9.5 }}>MI</span>
            </span>
          </div>
          <div style={{ position: "relative" }}>
            <div style={{ display: "flex", height: 30, borderRadius: 5, overflow: "hidden", background: "var(--paper-deep)" }}>
              {ordered.map((r) => (
                <div key={r.zone.id} onClick={() => setSel(sel === r.zone.id ? null : r.zone.id)}
                  title={r.zone.name}
                  style={{
                    width: r.pct + "%", background: r.zone.color, cursor: "pointer",
                    opacity: sel && sel !== r.zone.id ? 0.3 : 1, transition: "opacity .18s",
                    borderRight: "1px solid rgba(255,255,255,.45)",
                  }} />
              ))}
            </div>
            {/* 80/20 marker (ALL only) */}
            {mode === "all" && (
              <div style={{ position: "absolute", top: -4, bottom: -16, left: aerobicPct + "%", width: 0 }}>
                <div style={{ position: "absolute", top: 0, bottom: 18, left: -1, width: 2, background: "var(--ink)" }} />
                <div style={{ position: "absolute", bottom: 0, left: -14, fontFamily: "var(--font-mono)", fontSize: 8.5, color: "var(--ink)", whiteSpace: "nowrap", letterSpacing: ".4px" }}>
                  {Math.round(aerobicPct)}/{Math.round(agg.qualityPct)}
                </div>
              </div>
            )}
          </div>
          <div style={{ height: mode === "all" ? 18 : 6 }} />
        </div>

        {/* per-zone ledger */}
        <div style={{ padding: "4px 22px 2px" }}>
          {/* column header */}
          <div style={{
            display: "grid", gridTemplateColumns: "1.5fr 1.1fr 0.7fr 0.9fr", gap: 8,
            padding: "0 0 6px", borderBottom: "1px solid var(--rule)",
            fontFamily: "var(--font-mono)", fontSize: 8.5, color: "var(--ink-3)", letterSpacing: ".6px",
          }}>
            <span>ZONE</span><span>PACE</span><span style={{ textAlign: "right" }}>MI</span><span style={{ textAlign: "right" }}>SHARE · TREND</span>
          </div>
          {ordered.map((r) => {
            const d = trend[r.zone.id];
            const faster = d != null && d > 2, slower = d != null && d < -2;
            const dimmed = sel && sel !== r.zone.id;
            return (
              <div key={r.zone.id} onClick={() => setSel(sel === r.zone.id ? null : r.zone.id)}
                style={{
                  display: "grid", gridTemplateColumns: "1.5fr 1.1fr 0.7fr 0.9fr", gap: 8,
                  alignItems: "center", padding: "9px 0", borderBottom: "1px solid var(--rule)",
                  cursor: "pointer", opacity: dimmed ? 0.4 : 1, transition: "opacity .18s",
                }}>
                <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                  <span style={{ width: 9, height: 9, borderRadius: 2, background: r.zone.color, flexShrink: 0 }} />
                  <span style={{ fontFamily: "var(--font-display)", fontWeight: 600, fontSize: 15, color: "var(--ink)" }}>{r.zone.name}</span>
                </div>
                <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--ink-2)", fontVariantNumeric: "tabular-nums" }}>{paceRange(r.zone)}</span>
                <span style={{ textAlign: "right", fontFamily: "var(--font-mono)", fontSize: 15, fontWeight: 600, color: "var(--ink)", fontVariantNumeric: "tabular-nums" }}>{r.miles.toFixed(0)}</span>
                <div style={{ textAlign: "right" }}>
                  <span style={{ fontFamily: "var(--font-mono)", fontSize: 12.5, fontWeight: 600, color: "var(--ink)", fontVariantNumeric: "tabular-nums" }}>{r.pct.toFixed(0)}%</span>
                  <div style={{ fontFamily: "var(--font-mono)", fontSize: 9, marginTop: 1,
                    color: faster ? r.zone.ink : slower ? "var(--mood-tired)" : "var(--ink-3)" }}>
                    {d == null ? "—" : faster ? "↘ " + Math.abs(d) + "s" : slower ? "↗ " + Math.abs(d) + "s" : "steady"}
                  </div>
                </div>
              </div>
            );
          })}
        </div>

        {/* footer insight */}
        <div style={{ padding: "10px 22px 4px" }}>
          <p style={{ fontFamily: "var(--font-body)", fontSize: 12.5, lineHeight: 1.45, color: "var(--ink-2)", margin: 0 }}>
            <span style={{ color: "var(--mood-positive)", fontWeight: 700 }}>↘ faster</span> means that zone&rsquo;s
            average pace has dropped since week 1 — fitness, not effort. Easy is doing {Math.round(aerobicPct)}% of the work, right where it should be.
          </p>
        </div>
      </React.Fragment>
    );
  }

  window.LedgerBody = LedgerBody;
})();

/**
 * Group B detectors — inside-the-run trends on per-second Garmin/Strava
 * streams. B1 / B2 / B5 are live; B3 (cadence fade × niggles) and B4 (heat)
 * remain gated stubs until their signals are reliable on real data.
 *
 * All math lives in `streams.ts`; these functions gate, trend, and phrase.
 * Detection, not diagnosis: they observe HR/pace/recovery drifting and stop.
 */

import {
  type DetectCtx,
  type TrendCard,
  type Evidence,
  hiddenCard,
  slope,
} from "./contract.ts";
import {
  type StreamRun,
  bandLabel,
  cadenceFade,
  decouplingPct,
  hrInBand,
  hrr60,
  modalBand,
} from "./streams.ts";

const MIN_BAND_SEC_PER_WEEK = 240; // ≥4 min in the shared band to trust a week's mean HR
const MEANINGFUL_HR_DROP = 3; // bpm — below this, call it steady
const MEANINGFUL_DECOUPLE = 1.5; // percentage points
const MEANINGFUL_HRR_GAIN = 3; // bpm

// ─── B1 · Same pace, fewer beats ───────────────────────────────────────

export function detectB1(ctx: DetectCtx): TrendCard {
  const runs = ctx.streamRuns.filter((r) => r.hr.length > 0 && r.vel.length > 0);
  const band = modalBand(runs);
  if (!band) return hiddenCard("B1", "B");

  // Mean HR in the shared band, per week (weeks with enough seconds only).
  const perWeek = new Map<number, { sum: number; n: number; label: string }>();
  for (const run of runs) {
    if (run.weekIndex < 0) continue;
    const { sum, n } = hrInBand(run, band.band);
    if (n === 0) continue;
    const acc = perWeek.get(run.weekIndex) ?? { sum: 0, n: 0, label: run.weekLabel };
    acc.sum += sum;
    acc.n += n;
    perWeek.set(run.weekIndex, acc);
  }

  const weekly = [...perWeek.entries()]
    .filter(([, v]) => v.n >= MIN_BAND_SEC_PER_WEEK)
    .sort((a, b) => a[0] - b[0])
    .map(([, v]) => ({ hr: v.sum / v.n, label: v.label }));

  // Gate: ≥4 weeks with enough seconds in the band.
  if (weekly.length < 4) return hiddenCard("B1", "B");

  const hrs = weekly.map((w) => w.hr);
  const s = slope(hrs);
  const first = hrs[0];
  const last = hrs[hrs.length - 1];
  const drop = first - last;

  const evidence: Evidence[] = [
    { week: weekly[0].label, value: Math.round(first), label: "bpm" },
    { week: weekly[weekly.length - 1].label, value: Math.round(last), label: "bpm" },
  ];
  // Full series: weekly mean HR in the shared band. `down_good` — fewer
  // beats for the same pace reads as the win.
  const series = {
    points: hrs.map((h) => Math.round(h)),
    labels: weekly.map((w) => w.label),
    unit: "bpm",
    polarity: "down_good" as const,
  };

  if (s != null && s < 0 && drop >= MEANINGFUL_HR_DROP) {
    return {
      id: "B1",
      group: "B",
      status: "active",
      headline: "Same pace, fewer beats",
      body:
        `At your ${bandLabel(band.band)}-ish miles, your heart rate has come down from about ` +
        `${Math.round(first)} to ${Math.round(last)} bpm across this block — ${Math.round(drop)} ` +
        `fewer beats for the same pace. That's the aerobic base building.`,
      evidence,
      series,
      confidence: weekly.length >= 6 ? "high" : "medium",
    };
  }

  return {
    id: "B1",
    group: "B",
    status: "quiet",
    headline: "Your easy-pace heart rate is holding",
    body:
      `At your most-run pace, heart rate is steady around ${Math.round((first + last) / 2)} bpm — ` +
      `not climbing, not dropping. The engine's where it was.`,
    evidence,
    confidence: "low",
  };
}

// ─── B2 · The drift inside the long run ────────────────────────────────

const LONG_TYPES = new Set(["long", "long_run", "long wo", "steady", "mp_run", "progression"]);

function isLongish(run: StreamRun): boolean {
  const t = (run.type ?? "").toLowerCase();
  if (LONG_TYPES.has(t)) return true;
  // Fallback: any run with ≥70 min of paired samples reads as a long effort.
  return Math.min(run.hr.length, run.vel.length) >= 4200;
}

export function detectB2(ctx: DetectCtx): TrendCard {
  const points = ctx.streamRuns
    .filter(isLongish)
    .sort((a, b) => a.date.localeCompare(b.date))
    .map((r) => ({ pct: decouplingPct(r), label: r.weekLabel }))
    .filter((p): p is { pct: number; label: string } => p.pct != null);

  // Gate: ≥4 long/steady runs with a decoupling read.
  if (points.length < 4) return hiddenCard("B2", "B");

  const pcts = points.map((p) => p.pct);
  const s = slope(pcts);
  const earlyAvg = avg(pcts.slice(0, Math.max(1, Math.floor(pcts.length / 3))));
  const lateAvg = avg(pcts.slice(-Math.max(1, Math.floor(pcts.length / 3))));
  const improvement = earlyAvg - lateAvg;

  const evidence: Evidence[] = [
    { week: points[0].label, value: round1(earlyAvg), label: "% drift" },
    { week: points[points.length - 1].label, value: round1(lateAvg), label: "% drift" },
  ];
  // Full series: per-run decoupling %, with the durable band (<5%) behind it.
  const series = {
    points: pcts.map(round1),
    labels: points.map((p) => p.label),
    unit: "%",
    polarity: "down_good" as const,
    band: { lo: 0, hi: 5 },
  };

  if (s != null && s < 0 && improvement >= MEANINGFUL_DECOUPLE) {
    return {
      id: "B2",
      group: "B",
      status: "active",
      headline: "The drift inside the long run",
      body:
        `Your heart rate used to climb about ${round1(earlyAvg)}% through the back half of long runs. ` +
        `Lately it's ${round1(lateAvg)}%. You're holding together deeper into the run — the ` +
        `marathon-specific win.`,
      evidence,
      series,
      confidence: points.length >= 6 ? "high" : "medium",
    };
  }

  return {
    id: "B2",
    group: "B",
    status: "quiet",
    headline: "Your long-run drift is steady",
    body:
      `Heart-rate drift through the back half of your long runs is holding around ` +
      `${round1(lateAvg)}% — not opening up, not tightening. Durability's level for now.`,
    evidence,
    confidence: "low",
  };
}

// ─── B5 · How fast you bounce back ─────────────────────────────────────

export function detectB5(ctx: DetectCtx): TrendCard {
  const points = ctx.streamRuns
    .filter((r) => r.repEndIdx.length > 0)
    .sort((a, b) => a.date.localeCompare(b.date))
    .map((r) => ({ val: hrr60(r), label: r.weekLabel }))
    .filter((p): p is { val: number; label: string } => p.val != null);

  // Gate: ≥3 rep sessions with a recovery read.
  if (points.length < 3) return hiddenCard("B5", "B");

  const vals = points.map((p) => p.val);
  const s = slope(vals);
  const first = vals[0];
  const last = vals[vals.length - 1];
  const gain = last - first;

  const evidence: Evidence[] = [
    { week: points[0].label, value: Math.round(first), label: "bpm/60s" },
    { week: points[points.length - 1].label, value: Math.round(last), label: "bpm/60s" },
  ];
  // Full series: per-session 60-second HR recovery. `up_good` — bouncing
  // back faster is the win.
  const series = {
    points: vals.map((v) => Math.round(v)),
    labels: points.map((p) => p.label),
    unit: "bpm/60s",
    polarity: "up_good" as const,
  };

  if (s != null && s > 0 && gain >= MEANINGFUL_HRR_GAIN) {
    return {
      id: "B5",
      group: "B",
      status: "active",
      headline: "How fast you bounce back",
      body:
        `Between reps, your heart rate is coming down about ${Math.round(last)} beats a minute — ` +
        `up from ${Math.round(first)} earlier in the block. You're recovering faster inside the ` +
        `workout, not just between them.`,
      evidence,
      series,
      confidence: points.length >= 5 ? "high" : "medium",
    };
  }

  return {
    id: "B5",
    group: "B",
    status: "quiet",
    headline: "Your between-rep recovery is steady",
    body:
      `Your heart rate drops about ${Math.round((first + last) / 2)} beats in the minute after each ` +
      `rep — holding steady across the block.`,
    evidence,
    confidence: "low",
  };
}

// ─── B3 / B4 — still gated ─────────────────────────────────────────────
// B3 (cadence fade × niggles) and B4 (heat costing less) need reliable
// cadence/temp coverage + the niggle cross-ref; hidden until wired. The
// `cadenceFade` helper is ready in streams.ts for when B3 lands.
export function scaffoldBGated(_ctx: DetectCtx): TrendCard[] {
  void cadenceFade; // keep the helper referenced until B3 uses it
  return [hiddenCard("B3", "B"), hiddenCard("B4", "B")];
}

// ─── local helpers ─────────────────────────────────────────────────────

function avg(xs: number[]): number {
  return xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : 0;
}
function round1(x: number): number {
  return Math.round(x * 10) / 10;
}

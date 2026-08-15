// ============================================================================
// Fitness signal — pace-at-HR efficiency trend (WS-fitness)
//
// The OBJECTIVE backbone of the fitness verdict the daily Read expects: "same
// pace, HR trending down over weeks = fitter." Per-rep pace + HR already live
// in `running_workout_laps` and are detected per-session by the shared
// segmentation module — but until now they were never rolled up across
// sessions. This module does that roll-up.
//
// What it produces (all derived in-memory; no new source table):
//   • efficiency trends, bucketed by COMPARABLE effort (easy / threshold /
//     interval). Each bucket pools the qualifying portion of each session into
//     an efficiency factor EF = speed-per-heartbeat, then compares the last
//     ~4 weeks against the prior weeks. EF up = more speed per beat = fitter.
//     We surface the underlying pace+HR pair too, so the Read can say it the
//     way a coach would ("4:48 @ 162 → 4:43 @ 158") rather than quote a unitless
//     ratio.
//   • aerobic decoupling on long runs — within-run pace:HR drift (first half vs
//     second half), trended. Falling decoupling = better aerobic durability.
//
// Framing respects the hard rules: a trend is a DIRECTION over a stated, real
// window with a sample-based confidence — never a false point estimate, never a
// diagnosis. Pure functions, no I/O, unit-tested in
// _shared/__tests__/fitnessSignal.test.ts (run: deno test _shared/fitnessSignal.test.ts).
// ============================================================================

import {
  segmentFromLaps,
  fmtPace,
  type Bout,
  type LapInput,
  type PaceZones,
  type Zone,
} from "./workoutSegmentation.ts";

const METERS_PER_MILE = 1609.344;

// ── Windows ──
// Recent = last 4 weeks; baseline = the prior 8 weeks (weeks 5–12). A coach
// reads cycles, not fortnights — 12 weeks is the full scan, 4-vs-8 is the
// comparison. Kept as constants so tests and the renderer agree.
export const RECENT_WINDOW_DAYS = 28;
export const SCAN_WINDOW_DAYS = 84;

// HR sanity band — drop sensor dropouts/spikes so they don't poison the ratio.
const HR_MIN = 90;
const HR_MAX = 205;

// A direction is only called when the move clears noise.
const EF_DIR_PCT = 1.5; // EF % change to call improving/declining
const DECOUPLE_DIR_PCT = 1.0; // decoupling-% change to call a direction

// Minimum qualifying aerobic distance for an easy session to count (miles).
const MIN_EASY_MILES = 3;
// Minimum rep length for a rep to feed EF (seconds). Below ~90s HR never
// plateaus, so speed-per-beat under-reads the cost (measured 2026-08-14 —
// the 200s session: 0/8 reps settled). Matches repSignal.REP_MIN_S.
const EF_REP_MIN_S = 90;
// Minimum sustained running time for a long-run decoupling read (seconds).
const MIN_DECOUPLE_SECONDS = 40 * 60;

/** "interval" remains in the type because persisted `athlete_state` rows and
 *  the Ask `efficiency` analyzer's enum still carry it — but as of 2026-08-15
 *  this module NO LONGER PRODUCES interval trends (see accumulateEfficiency).
 *  Consumers must treat it as historical. */
export type EffortBucket = "easy" | "threshold" | "interval";

export interface SessionInput {
  /** Calendar date (YYYY-MM-DD). */
  date: string;
  laps: LapInput[];
}

export interface EfficiencyTrend {
  bucket: EffortBucket;
  recent_samples: number;
  baseline_samples: number;
  /** Real span of the baseline window actually covered, in days — so the Read
   *  can state an honest window ("vs the prior ~8 weeks"), never a made-up one. */
  baseline_days: number;
  /** speed-per-bpm (m·min⁻¹ per bpm). Higher = fitter. */
  ef_recent: number;
  ef_baseline: number;
  /** + = more efficient now (fitter). */
  ef_delta_pct: number;
  /** Pooled work/aerobic pace (sec/mi) and HR for each window — for "4:43 @ 158" prose. */
  pace_recent_sec: number;
  hr_recent: number;
  pace_baseline_sec: number;
  hr_baseline: number;
  direction: "improving" | "flat" | "declining";
  confidence: "high" | "medium" | "low";
}

export interface DecouplingTrend {
  recent_pct: number | null;
  baseline_pct: number | null;
  recent_samples: number;
  baseline_samples: number;
  /** improving = decoupling getting smaller (more durable). */
  direction: "improving" | "flat" | "declining" | null;
}

export interface FitnessSignal {
  window_days: number;
  /** Buckets that cleared the minimum-sample bar, sharpest signal first. */
  efficiency: EfficiencyTrend[];
  decoupling: DecouplingTrend | null;
  /** One plain-language objective verdict the Read may surface, or null when
   *  evidence is too thin. Descriptive only (no prescription, no diagnosis). */
  verdict: string | null;
  confidence: "high" | "medium" | "low";
}

// ── Per-window accumulator (pooled over sessions) ──

interface Pool {
  meters: number;
  seconds: number;
  hrWeighted: number; // Σ hr × seconds
  hrSeconds: number; // Σ seconds with valid hr
  sessions: number;
  earliestAgeDays: number; // largest age (oldest session) seen — for baseline span
}

function emptyPool(): Pool {
  return { meters: 0, seconds: 0, hrWeighted: 0, hrSeconds: 0, sessions: 0, earliestAgeDays: 0 };
}

/** Pooled pace (sec/mi) from a pool, or null if no distance/time. */
function poolPace(p: Pool): number | null {
  if (p.meters <= 0 || p.seconds <= 0) return null;
  return (p.seconds / p.meters) * METERS_PER_MILE;
}
/** Pooled time-weighted HR, or null. */
function poolHr(p: Pool): number | null {
  if (p.hrSeconds <= 0) return null;
  return p.hrWeighted / p.hrSeconds;
}
/** Efficiency factor = speed (m/min) / HR. Higher = fitter. null if incomplete. */
function poolEf(p: Pool): number | null {
  const hr = poolHr(p);
  if (hr == null || hr <= 0 || p.seconds <= 0) return null;
  const speedMPerMin = p.meters / (p.seconds / 60);
  return speedMPerMin / hr;
}

// ── Bucketing one session ──

const QUALITY_THRESHOLD_ZONES: ReadonlySet<Zone> = new Set<Zone>(["hmp", "10k", "mp"]);
const QUALITY_INTERVAL_ZONES: ReadonlySet<Zone> = new Set<Zone>(["5k", "3k", "mile"]);
// Aerobic background that defines an "easy" session's qualifying portion.
const AEROBIC_ZONES: ReadonlySet<Zone> = new Set<Zone>(["easy", "moderate", "steady"]);

const dominantRepZone = (reps: Bout[]): Zone | null => {
  if (reps.length === 0) return null;
  const sec = new Map<Zone, number>();
  for (const r of reps) sec.set(r.zone, (sec.get(r.zone) ?? 0) + r.seconds);
  let best: Zone | null = null, bestSec = -1;
  for (const [z, s] of sec) if (s > bestSec) { best = z; bestSec = s; }
  return best;
};

const validHr = (h: number | null): h is number =>
  h != null && h >= HR_MIN && h <= HR_MAX;

/** Add the qualifying portion of a session to the right window pool. Returns
 *  the bucket it landed in (or null if it didn't qualify for an EF bucket). */
function accumulateEfficiency(
  laps: LapInput[],
  zones: PaceZones,
  ageDays: number,
  pools: Record<EffortBucket, { recent: Pool; baseline: Pool }>,
): EffortBucket | null {
  const seg = segmentFromLaps(laps, zones);
  const within = (b: Bout) => b.paceSecPerMile > 0 && validHr(b.avgHr);

  // Quality session: pool the WORK reps (comparable hard efforts).
  //
  // (2026-08-15) TWO AMENDMENTS, both measured — CURRENT-FITNESS-APPLY.md §2.1:
  //  • The INTERVAL bucket no longer feeds EF. Reps in 5k/3k/mile zones are
  //    short, and HR lags effort by 30–60s: on the 200s calibration session
  //    0 of 8 reps reached a plateau and the average HR under-read the true
  //    cost in a way that VARIES with rep length. Speed-per-beat on such reps
  //    is systematically flattering and not comparable across sessions.
  //    Threshold and easy carry the EF read; short reps are load, not cost.
  //    (`repSignal.ts` owns the short-rep story via hrr60, gated ≥90s.)
  //  • Within a threshold session, only reps ≥ EF_REP_MIN_S pool — the same
  //    plateau physics, applied per rep. A 3×2mi session is unaffected; a
  //    mixed set's 45s bursts fall out.
  if (seg.reps.length >= 2) {
    const dz = dominantRepZone(seg.reps);
    const bucket: EffortBucket | null =
      dz && QUALITY_THRESHOLD_ZONES.has(dz) ? "threshold" : null;
    if (bucket) {
      const reps = seg.reps.filter((b) => within(b) && b.seconds >= EF_REP_MIN_S);
      if (reps.length >= 2) {
        const target = ageDays <= RECENT_WINDOW_DAYS ? "recent" : "baseline";
        addBouts(pools[bucket][target], reps, ageDays);
        return bucket;
      }
    }
    return null;
  }

  // Easy session: pool the aerobic bouts (steady continuous effort — the most
  // controlled, most frequent fitness read). Only true easy/recovery runs, not
  // long runs (those feed decoupling) and not quality.
  if (seg.workoutKind === "easy" || seg.workoutKind === "recovery") {
    const aerobic = seg.bouts.filter(
      (b) => !b.isRest && AEROBIC_ZONES.has(b.zone) && within(b),
    );
    const meters = aerobic.reduce((s, b) => s + b.distanceMeters, 0);
    if (meters >= MIN_EASY_MILES * METERS_PER_MILE) {
      const target = ageDays <= RECENT_WINDOW_DAYS ? "recent" : "baseline";
      addBouts(pools.easy[target], aerobic, ageDays);
      return "easy";
    }
  }
  return null;
}

function addBouts(pool: Pool, bouts: Bout[], ageDays: number): void {
  for (const b of bouts) {
    pool.meters += b.distanceMeters;
    pool.seconds += b.seconds;
    if (validHr(b.avgHr)) {
      pool.hrWeighted += b.avgHr * b.seconds;
      pool.hrSeconds += b.seconds;
    }
  }
  pool.sessions += 1;
  if (ageDays > pool.earliestAgeDays) pool.earliestAgeDays = ageDays;
}

// ── Decoupling on a single sustained effort (long run / continuous tempo) ──

/** Aerobic decoupling % for one session: (EF_firstHalf − EF_secondHalf) /
 *  EF_firstHalf × 100, split by cumulative time. Positive = HR drifted up
 *  relative to pace (less durable). null when not a long-enough sustained run. */
export function sessionDecouplingPct(laps: LapInput[], zones: PaceZones): number | null {
  const seg = segmentFromLaps(laps, zones);
  // Only read durability on long runs — a continuous aerobic effort, no rep
  // structure. (Quality sessions have rest laps and rep dynamics; their drift
  // is `hr_drift_pct`, a different lens.)
  if (seg.workoutKind !== "long_run") return null;
  const run = seg.bouts.filter(
    (b) => !b.isRest && b.paceSecPerMile > 0 && validHr(b.avgHr) && b.distanceMeters > 0,
  );
  const total = run.reduce((s, b) => s + b.seconds, 0);
  if (total < MIN_DECOUPLE_SECONDS) return null;

  const half = total / 2;
  let acc = 0;
  const first: Bout[] = [];
  const second: Bout[] = [];
  for (const b of run) {
    if (acc + b.seconds / 2 <= half) first.push(b);
    else second.push(b);
    acc += b.seconds;
  }
  const ef = (bouts: Bout[]): number | null => {
    const m = bouts.reduce((s, b) => s + b.distanceMeters, 0);
    const sec = bouts.reduce((s, b) => s + b.seconds, 0);
    const hrSec = bouts.reduce((s, b) => s + b.seconds, 0);
    const hrW = bouts.reduce((s, b) => s + (b.avgHr ?? 0) * b.seconds, 0);
    if (m <= 0 || sec <= 0 || hrSec <= 0) return null;
    const speed = m / (sec / 60);
    return speed / (hrW / hrSec);
  };
  const efFirst = ef(first);
  const efSecond = ef(second);
  if (efFirst == null || efSecond == null || efFirst <= 0) return null;
  return ((efFirst - efSecond) / efFirst) * 100;
}

// ── Public entry point ──

const round1 = (x: number): number => Math.round(x * 10) / 10;
const round3 = (x: number): number => Math.round(x * 1000) / 1000;

function confFromSamples(recent: number, baseline: number): "high" | "medium" | "low" {
  if (recent >= 3 && baseline >= 4) return "high";
  if (recent >= 2 && baseline >= 2) return "medium";
  return "low";
}

const BUCKET_PRIORITY: EffortBucket[] = ["threshold", "easy"]; // interval retired 2026-08-15
const BUCKET_LABEL: Record<EffortBucket, string> = {
  easy: "easy runs",
  threshold: "threshold (LT) work",
  interval: "interval (VO2) work",
};

/**
 * Build the fitness signal from a window of sessions. `asOf` anchors the
 * recent/baseline split (defaults to now) so the computation is deterministic
 * and testable. Sessions outside SCAN_WINDOW_DAYS are ignored.
 */
export function computeFitnessSignal(
  sessions: SessionInput[],
  zones: PaceZones,
  asOf: Date = new Date(),
): FitnessSignal {
  const pools: Record<EffortBucket, { recent: Pool; baseline: Pool }> = {
    easy: { recent: emptyPool(), baseline: emptyPool() },
    threshold: { recent: emptyPool(), baseline: emptyPool() },
    interval: { recent: emptyPool(), baseline: emptyPool() },
  };
  const decoupleRecent: number[] = [];
  const decoupleBaseline: number[] = [];

  const asOfMs = asOf.getTime();
  for (const s of sessions) {
    const ageDays = (asOfMs - new Date(s.date).getTime()) / 86400000;
    if (!isFinite(ageDays) || ageDays < 0 || ageDays > SCAN_WINDOW_DAYS) continue;
    accumulateEfficiency(s.laps, zones, ageDays, pools);
    const dec = sessionDecouplingPct(s.laps, zones);
    if (dec != null) {
      if (ageDays <= RECENT_WINDOW_DAYS) decoupleRecent.push(dec);
      else decoupleBaseline.push(dec);
    }
  }

  // ── Efficiency trends per bucket ──
  const efficiency: EfficiencyTrend[] = [];
  for (const bucket of BUCKET_PRIORITY) {
    const r = pools[bucket].recent;
    const b = pools[bucket].baseline;
    // Need both windows populated to call a trend.
    if (r.sessions < 2 || b.sessions < 2) continue;
    const efR = poolEf(r), efB = poolEf(b);
    const paceR = poolPace(r), paceB = poolPace(b);
    const hrR = poolHr(r), hrB = poolHr(b);
    if (efR == null || efB == null || paceR == null || paceB == null || hrR == null || hrB == null) continue;
    const deltaPct = ((efR - efB) / efB) * 100;
    const direction = deltaPct >= EF_DIR_PCT ? "improving"
      : deltaPct <= -EF_DIR_PCT ? "declining" : "flat";
    efficiency.push({
      bucket,
      recent_samples: r.sessions,
      baseline_samples: b.sessions,
      baseline_days: Math.round(b.earliestAgeDays),
      ef_recent: round3(efR),
      ef_baseline: round3(efB),
      ef_delta_pct: round1(deltaPct),
      pace_recent_sec: Math.round(paceR),
      hr_recent: Math.round(hrR),
      pace_baseline_sec: Math.round(paceB),
      hr_baseline: Math.round(hrB),
      direction,
      confidence: confFromSamples(r.sessions, b.sessions),
    });
  }

  // ── Decoupling trend ──
  const mean = (xs: number[]): number | null =>
    xs.length ? xs.reduce((s, x) => s + x, 0) / xs.length : null;
  let decoupling: DecouplingTrend | null = null;
  const decR = mean(decoupleRecent);
  const decB = mean(decoupleBaseline);
  if (decR != null || decB != null) {
    let direction: DecouplingTrend["direction"] = null;
    if (decR != null && decB != null) {
      direction = decR <= decB - DECOUPLE_DIR_PCT ? "improving"
        : decR >= decB + DECOUPLE_DIR_PCT ? "declining" : "flat";
    }
    decoupling = {
      recent_pct: decR != null ? round1(decR) : null,
      baseline_pct: decB != null ? round1(decB) : null,
      recent_samples: decoupleRecent.length,
      baseline_samples: decoupleBaseline.length,
      direction,
    };
  }

  // ── Headline verdict — pick the sharpest bucket that has a real direction,
  //    else the steadiest. Descriptive, windowed, never a point prediction. ──
  const verdict = buildVerdict(efficiency, decoupling);

  // Overall confidence = best bucket we have (efficiency leads; decoupling is a
  // supporting read, so it can't lift confidence on its own).
  const conf = efficiency.reduce<"high" | "medium" | "low">((best, e) => {
    const rank = (c: string) => (c === "high" ? 3 : c === "medium" ? 2 : 1);
    return rank(e.confidence) > rank(best) ? e.confidence : best;
  }, "low");

  return {
    window_days: SCAN_WINDOW_DAYS,
    efficiency,
    decoupling,
    verdict,
    confidence: efficiency.length === 0 ? "low" : conf,
  };
}

function weeksFromDays(days: number): number {
  return Math.max(1, Math.round(days / 7));
}

function buildVerdict(
  efficiency: EfficiencyTrend[],
  decoupling: DecouplingTrend | null,
): string | null {
  // Prefer a bucket with a called direction; among those, sharpest effort first.
  const moving = efficiency.filter((e) => e.direction !== "flat");
  const chosen = moving[0] ?? efficiency[0];
  if (!chosen) {
    // No EF trend — fall back to a durability statement if we have one.
    if (decoupling?.direction === "improving" && decoupling.recent_pct != null) {
      return `Long-run durability is improving — aerobic decoupling down to ${decoupling.recent_pct}% from ${decoupling.baseline_pct}%.`;
    }
    return null;
  }

  const weeks = weeksFromDays(chosen.baseline_days);
  const label = BUCKET_LABEL[chosen.bucket];
  const pR = fmtPace(chosen.pace_recent_sec);
  const pB = fmtPace(chosen.pace_baseline_sec);
  const same = pR === pB;

  let core: string;
  if (chosen.direction === "improving") {
    // Faster, lower, or both — say which honestly from the pace/HR pair.
    if (same) {
      core = `at ${pR}/mi, HR ${chosen.hr_baseline} → ${chosen.hr_recent} bpm — same pace, lower cost`;
    } else {
      core = `${pB} @ ${chosen.hr_baseline} → ${pR} @ ${chosen.hr_recent} (pace @ HR), more speed per beat`;
    }
    return `${cap(label)} are trending fitter over the last ${weeks} weeks: ${core}.`;
  }
  if (chosen.direction === "declining") {
    if (same) {
      core = `at ${pR}/mi, HR ${chosen.hr_baseline} → ${chosen.hr_recent} bpm — same pace costing more`;
    } else {
      core = `${pB} @ ${chosen.hr_baseline} → ${pR} @ ${chosen.hr_recent} (pace @ HR)`;
    }
    return `${cap(label)} efficiency has slipped over the last ${weeks} weeks: ${core} — worth watching against how training's felt.`;
  }
  // Flat.
  return `${cap(label)} efficiency is holding over the last ${weeks} weeks — ${pR}/mi around ${chosen.hr_recent} bpm, steady.`;
}

function cap(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

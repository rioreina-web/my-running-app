/**
 * Recovery-segmented work-bout detection.
 *
 * The core rule of workout parsing: **a rep is bounded by a recovery, not by a
 * distance marker.** Two fast 1-mile splits with nothing between them are ONE
 * continuous 2-mile rep — they only become two reps if a recovery (a jog or a
 * standing rest) separates them. GPS auto-lap markers and per-km/-mile splits
 * lie about this constantly; the recoveries are the ground truth for structure.
 *
 * This module reads the raw stream (time / distance / velocity) and returns the
 * continuous work bouts and the recoveries between them. It is deterministic and
 * dependency-free so it can be unit-tested and fed to the LLM parser as a
 * pre-segmented hint (the model labels and reconciles with typed notes; it does
 * NOT have to guess where one rep ends and the next begins).
 *
 * Pure functions only — see the rule evaluators / other shared helpers for the
 * testability convention.
 */

export interface RawStreams {
  time?: number[];          // seconds, monotonically increasing
  distance?: number[];      // cumulative meters
  velocity_smooth?: number[]; // m/s
}

export type Segment = "work" | "recovery";

export interface WorkBout {
  kind: "work";
  index: number;            // 1-based work-bout number
  start_s: number;
  end_s: number;
  duration_s: number;
  start_m: number;
  end_m: number;
  distance_m: number;
  avg_vel_ms: number;
  avg_pace_per_mile: string; // "M:SS"
  avg_pace_per_km: string;   // "M:SS"
}

export interface Recovery {
  kind: "recovery";
  after_bout: number;       // the work-bout index this recovery follows
  duration_s: number;
  distance_m: number;
  avg_vel_ms: number;
  style: "standing" | "jog"; // standing rest vs. moving recovery
}

export type BoutOrRecovery = WorkBout | Recovery;

export interface DetectOptions {
  /**
   * A point counts as recovery when its velocity falls below this fraction of
   * the session's work velocity (median of moving points). 0.7 ≈ "noticeably
   * slower than the reps were run."
   */
  recoveryFrac?: number;
  /** Below this absolute velocity (m/s) the athlete is effectively stopped. */
  standingVelMs?: number;
  /**
   * A dip must last at least this long to actually separate two reps. Stops
   * brief GPS noise / a single slow tick inside a rep from fracturing it.
   */
  minRecoverySec?: number;
  /** A work segment shorter than this is folded into the surrounding recovery. */
  minWorkSec?: number;
}

const DEFAULTS: Required<DetectOptions> = {
  recoveryFrac: 0.7,
  standingVelMs: 0.8,
  minRecoverySec: 20,
  minWorkSec: 15,
};

// A lap that is short in BOTH distance and duration is a GPS artifact — an
// auto-lap tick at the end of a run, or an accidental lap press — not a rep or a
// recovery. Dropped from the lap segmenter so it can't skew the fast/slow split
// or masquerade as a separator. (A standing rest is short in distance but NOT in
// time, so it clears the duration bound and still separates the reps it sits
// between.)
const FRAGMENT_MAX_METERS = 40;
const FRAGMENT_MAX_SECONDS = 15;

/**
 * Standard interval distances, in meters, with their athlete-facing label.
 * Used to snap a bout's true length to the rep distance the athlete most likely
 * meant — INDEPENDENT of how the watch lapped. A bout that measures ~1000m is a
 * "1k" rep even if the GPS auto-lapped every mile, and a ~1609m bout is "1mi"
 * even if the watch recorded kilometer splits. The split unit and the rep unit
 * are not the same thing.
 */
const STANDARD_REPS: Array<{ m: number; label: string }> = [
  { m: 200, label: "200m" },
  { m: 300, label: "300m" },
  { m: 400, label: "400m" },
  { m: 600, label: "600m" },
  { m: 800, label: "800m" },
  { m: 1000, label: "1k" },
  { m: 1200, label: "1200m" },
  { m: 1500, label: "1.5k" },
  { m: 1609, label: "1mi" },
  { m: 2000, label: "2k" },
  { m: 2414, label: "1.5mi" },
  { m: 3000, label: "3k" },
  { m: 3219, label: "2mi" },
  { m: 5000, label: "5k" },
];

export interface NearestRep {
  label: string | null; // null when the bout is too ragged to snap confidently
  meters: number | null;
  delta_pct: number | null; // signed % the bout differs from the snapped distance
  ambiguous: boolean;       // true when two standard distances are ~equally close (e.g. 1.5k vs 1mi)
}

/**
 * Standard TIME-based rep durations, in seconds, with their athlete-facing
 * label. Reps are often prescribed by time ("10'", "5' on", "3 × 8 min") rather
 * than distance — especially tempo/threshold work. A bout that lasts ~600s is a
 * "10'" rep regardless of how far it covered. Distance and time are two lenses
 * on the same bout; the athlete's typed intent picks which one is the rep unit.
 */
const STANDARD_TIME_REPS: Array<{ s: number; label: string }> = [
  { s: 30, label: "30\"" },
  { s: 60, label: "1'" },
  { s: 90, label: "90\"" },
  { s: 120, label: "2'" },
  { s: 180, label: "3'" },
  { s: 240, label: "4'" },
  { s: 300, label: "5'" },
  { s: 360, label: "6'" },
  { s: 480, label: "8'" },
  { s: 600, label: "10'" },
  { s: 720, label: "12'" },
  { s: 900, label: "15'" },
  { s: 1200, label: "20'" },
  { s: 1800, label: "30'" },
];

export interface NearestTimeRep {
  label: string | null;
  seconds: number | null;
  delta_pct: number | null;
  ambiguous: boolean;
}

/**
 * Snap a measured bout duration to the nearest standard time-based rep. Same
 * contract as nearestRepDistance: label=null when nothing is within tolerance
 * (a ragged duration — defer to typed intent).
 */
export function nearestTimeRep(durationSeconds: number, tolerancePct = 12): NearestTimeRep {
  if (!isFinite(durationSeconds) || durationSeconds <= 0) {
    return { label: null, seconds: null, delta_pct: null, ambiguous: false };
  }
  const ranked = STANDARD_TIME_REPS
    .map((r) => ({ ...r, absPct: Math.abs((durationSeconds - r.s) / r.s) * 100 }))
    .sort((a, b) => a.absPct - b.absPct);
  const best = ranked[0];
  const second = ranked[1];
  if (best.absPct > tolerancePct) {
    return { label: null, seconds: null, delta_pct: null, ambiguous: false };
  }
  return {
    label: best.label,
    seconds: best.s,
    delta_pct: Math.round(((durationSeconds - best.s) / best.s) * 100),
    ambiguous: !!second && second.absPct <= tolerancePct,
  };
}

/**
 * Snap a measured bout distance to the nearest standard rep distance, with a
 * tolerance. Returns label=null when nothing is within ~12% (a genuinely ragged
 * effort — defer to the athlete's typed intent). Flags ambiguity when the two
 * closest standards are both within tolerance (e.g. 1500m vs 1609m).
 */
export function nearestRepDistance(distanceMeters: number, tolerancePct = 12): NearestRep {
  if (!isFinite(distanceMeters) || distanceMeters <= 0) {
    return { label: null, meters: null, delta_pct: null, ambiguous: false };
  }
  const ranked = STANDARD_REPS
    .map((r) => ({ ...r, absPct: Math.abs((distanceMeters - r.m) / r.m) * 100 }))
    .sort((a, b) => a.absPct - b.absPct);
  const best = ranked[0];
  const second = ranked[1];
  if (best.absPct > tolerancePct) {
    return { label: null, meters: null, delta_pct: null, ambiguous: false };
  }
  return {
    label: best.label,
    meters: best.m,
    delta_pct: Math.round(((distanceMeters - best.m) / best.m) * 100),
    ambiguous: !!second && second.absPct <= tolerancePct,
  };
}

function pace(secPerUnit: number): string {
  if (!isFinite(secPerUnit) || secPerUnit <= 0) return "--:--";
  const m = Math.floor(secPerUnit / 60);
  const s = Math.round(secPerUnit % 60);
  // carry the rounding boundary (e.g. 7:60 -> 8:00)
  const mm = s === 60 ? m + 1 : m;
  const ss = s === 60 ? 0 : s;
  return `${mm}:${String(ss).padStart(2, "0")}`;
}

function median(xs: number[]): number {
  if (xs.length === 0) return 0;
  const sorted = [...xs].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

/**
 * Adaptive work/recovery velocity boundary for a set of laps.
 *
 * The fixed "recovery = below `recoveryFrac` (0.7) of work pace" rule assumes an
 * athlete's recovery jogs are ≥30% slower than their reps. That breaks for a
 * fast runner whose recoveries are EASY, not slow: 6 × 1mi @ ~5:30 with ~400m
 * jog recoveries @ ~6:30 puts the recoveries at ~85% of rep velocity — above the
 * 0.7 cutoff — so every recovery reads as more work and the reps glue into one
 * block. No single fixed fraction can fix this: a recovery at 0.85 of rep pace
 * and a legit tempo lap at 0.85 of a faster interval's pace are indistinguishable
 * by ratio alone. The *gap* is the signal, not the ratio.
 *
 * So find the natural split between the fast (rep) laps and the slower (recovery)
 * laps with Otsu's method — the threshold that best separates the velocities into
 * two groups — and only trust it when the laps are genuinely BIMODAL: the two
 * groups must be separated by a clear empty band (much wider than the spacing
 * *within* either group) and the fast group must be meaningfully faster. A steady
 * run (one cluster) or a smooth progression (evenly spaced, no band) fails those
 * guards and returns null, so the caller keeps the fixed-fraction fallback and
 * those sessions behave exactly as before.
 *
 * Returns the boundary velocity (m/s) — laps below it are recovery — or null when
 * the laps aren't clearly bimodal.
 */
export function bimodalWorkRecoveryBoundary(
  vels: number[],
  standingVelMs: number,
): number | null {
  // Ignore near-standing points so a lone stop/cooldown fragment can't hijack
  // the split — the two clusters we're separating are the running laps.
  const v = vels.filter((x) => x > standingVelMs).sort((a, b) => a - b);
  if (v.length < 4) return null;

  const total = v.reduce((a, b) => a + b, 0);

  // Otsu: choose split index k (low = v[0..k], high = v[k+1..]) that maximizes
  // between-group separation w0·w1·(μ_high − μ_low)².
  let bestK = -1;
  let bestScore = -1;
  let cumN = 0;
  let cumSum = 0;
  for (let k = 0; k < v.length - 1; k++) {
    cumN += 1;
    cumSum += v[k];
    const w0 = cumN / v.length;
    const w1 = 1 - w0;
    const mu0 = cumSum / cumN;
    const mu1 = (total - cumSum) / (v.length - cumN);
    const score = w0 * w1 * (mu1 - mu0) ** 2;
    if (score > bestScore) {
      bestScore = score;
      bestK = k;
    }
  }
  if (bestK < 0) return null;

  const low = v.slice(0, bestK + 1);
  const high = v.slice(bestK + 1);
  const muLow = low.reduce((a, b) => a + b, 0) / low.length;
  const muHigh = high.reduce((a, b) => a + b, 0) / high.length;

  // Guard 1: the fast group must be meaningfully faster than the slow group.
  // Rejects a steady run (one cluster split down the middle → ratio ≈ 1).
  if (muLow <= 0 || muHigh / muLow < 1.1) return null;

  // Guard 2: a real empty band between the groups. The gap that separates them
  // must dwarf the typical spacing WITHIN the groups — otherwise the data is a
  // smooth continuum (a progression), not two distinct efforts.
  const band = high[0] - low[low.length - 1];
  const innerGaps: number[] = [];
  for (let i = 1; i < low.length; i++) innerGaps.push(low[i] - low[i - 1]);
  for (let i = 1; i < high.length; i++) innerGaps.push(high[i] - high[i - 1]);
  const meanInner = innerGaps.length
    ? innerGaps.reduce((a, b) => a + b, 0) / innerGaps.length
    : 0;
  if (meanInner > 0 && band < 2.5 * meanInner) return null;

  return (low[low.length - 1] + high[0]) / 2;
}

/**
 * Bimodal work/recovery boundary for DENSE per-second stream velocities.
 *
 * The lap path's gap test doesn't work here — adjacent per-second samples are
 * ~0 apart, so there's no "empty band" to find. Detect the two speed clusters
 * from the velocity DISTRIBUTION instead: histogram the moving samples, and if
 * there are two clear modes (a rep-pace peak and a recovery-pace peak) separated
 * by a real valley, return the valley velocity as the work/recovery boundary.
 *
 * Deliberately conservative — it only fires on a genuinely two-peaked
 * distribution. A steady run (one peak), a smooth progression (a broad plateau,
 * no valley), and a standing-rest interval session (the rests are below
 * `standingVelMs` and never enter the histogram, leaving one moving peak) all
 * return null, so the caller keeps the exact fixed-fraction fallback and their
 * behavior is unchanged. Only fast-moving-recovery intervals — the case the 0.7
 * cutoff mislabels — produce two moving peaks and get the corrected boundary.
 */
export function bimodalBoundaryFromDensity(
  vels: number[],
  standingVelMs: number,
): number | null {
  const v = vels.filter((x) => x > standingVelMs);
  if (v.length < 60) return null; // too few samples to trust a distribution

  let lo = Infinity, hi = -Infinity;
  for (const x of v) {
    if (x < lo) lo = x;
    if (x > hi) hi = x;
  }
  if (hi - lo < 0.5) return null; // essentially one speed → not bimodal

  const BINS = 24;
  const width = (hi - lo) / BINS;
  const hist = new Array(BINS).fill(0);
  for (const x of v) {
    let b = Math.floor((x - lo) / width);
    if (b >= BINS) b = BINS - 1;
    if (b < 0) b = 0;
    hist[b] += 1;
  }

  // 3-bin moving-average smoothing to tame per-second GPS noise.
  const sm = new Array(BINS).fill(0);
  for (let i = 0; i < BINS; i++) {
    let s = 0, cnt = 0;
    for (let j = i - 1; j <= i + 1; j++) {
      if (j >= 0 && j < BINS) { s += hist[j]; cnt += 1; }
    }
    sm[i] = s / cnt;
  }

  // Mode 1 = tallest bin. Mode 2 = tallest bin at a genuinely different speed
  // (≥ ~15% of the velocity range away from mode 1).
  let m1 = 0;
  for (let i = 1; i < BINS; i++) if (sm[i] > sm[m1]) m1 = i;
  const SEP = Math.max(2, Math.round(BINS * 0.15));
  let m2 = -1;
  for (let i = 0; i < BINS; i++) {
    if (Math.abs(i - m1) < SEP) continue;
    if (m2 < 0 || sm[i] > sm[m2]) m2 = i;
  }
  if (m2 < 0) return null;

  const a = Math.min(m1, m2);
  const b = Math.max(m1, m2);
  if (b - a < 2) return null; // modes adjacent → no room for a valley

  const peakHi = Math.max(sm[m1], sm[m2]);
  const peakLo = Math.min(sm[m1], sm[m2]);
  // The second mode must carry real mass, not be a noise bump.
  if (peakLo < 0.15 * peakHi) return null;

  // Reject a multi-modal continuum (e.g. a stepped progression): if a peak
  // comparable to the smaller of our two modes sits OUTSIDE them, this isn't a
  // clean two-cluster (rep/recovery) distribution and we must not split it.
  let outsideMax = 0;
  for (let i = 0; i < BINS; i++) {
    if (i >= a && i <= b) continue;
    if (sm[i] > outsideMax) outsideMax = sm[i];
  }
  if (outsideMax > 0.5 * peakLo) return null;

  // Valley = the lowest smoothed count strictly between the two modes; require
  // a real trough (well below the smaller peak), else it's one broad cluster.
  let minC = Infinity;
  for (let i = a + 1; i < b; i++) if (sm[i] < minC) minC = sm[i];
  if (minC > 0.5 * peakLo) return null;
  const valleyBins: number[] = [];
  for (let i = a + 1; i < b; i++) if (sm[i] === minC) valleyBins.push(i);
  const valley = valleyBins[Math.floor(valleyBins.length / 2)];

  return lo + (valley + 0.5) * width;
}

/**
 * Segment a run into recovery-bounded work bouts.
 *
 * Returns the bouts and recoveries in chronological order, plus the work
 * velocity baseline used. Continuous fast running stays a single bout no matter
 * how far it goes; only a sustained recovery starts a new one.
 */
export function detectWorkBouts(
  streams: RawStreams,
  opts: DetectOptions = {},
): { segments: BoutOrRecovery[]; workVelMs: number } {
  const o = { ...DEFAULTS, ...opts };
  const time = streams.time ?? [];
  const dist = streams.distance ?? [];
  let vel = streams.velocity_smooth ?? [];

  const n = Math.min(
    time.length || Infinity,
    dist.length || Infinity,
    vel.length || Infinity,
  );
  if (!isFinite(n) || n < 2) return { segments: [], workVelMs: 0 };

  // Derive velocity from distance/time if the stream is absent or all-zero.
  if (vel.length < n || vel.slice(0, n).every((v) => !v)) {
    vel = new Array(n).fill(0);
    for (let i = 1; i < n; i++) {
      const dt = time[i] - time[i - 1];
      vel[i] = dt > 0 ? (dist[i] - dist[i - 1]) / dt : vel[i - 1];
    }
    vel[0] = vel[1] ?? 0;
  }

  // Work velocity = median of the moving points (exclude near-standing).
  const moving = vel.slice(0, n).filter((v) => v > o.standingVelMs);
  const workVel = median(moving);
  if (workVel <= 0) return { segments: [], workVelMs: 0 };

  // Prefer the adaptive bimodal boundary when the run's velocity distribution
  // has two clear speed clusters (fast reps + easy-but-not-slow recoveries) —
  // the same blind spot the lap path had. Fall back to the fixed fraction for
  // single-cluster runs (steady, progression, standing-rest intervals), leaving
  // them unchanged.
  const densityBoundary = bimodalBoundaryFromDensity(vel.slice(0, n), o.standingVelMs);
  const recoveryThreshold = densityBoundary ?? o.recoveryFrac * workVel;

  // 1) Per-point classification.
  const cls: Segment[] = new Array(n);
  for (let i = 0; i < n; i++) {
    cls[i] = vel[i] < recoveryThreshold ? "recovery" : "work";
  }

  // 2) Collapse into runs of like class.
  type Run = { seg: Segment; lo: number; hi: number };
  const runs: Run[] = [];
  for (let i = 0; i < n; i++) {
    const last = runs[runs.length - 1];
    if (last && last.seg === cls[i]) last.hi = i;
    else runs.push({ seg: cls[i], lo: i, hi: i });
  }

  const durOf = (r: Run) => time[r.hi] - time[r.lo];

  // 3) Drop sub-threshold recoveries (GPS noise / one slow tick) by reclassing
  //    them to work, then drop sub-threshold work blips into recovery. Re-merge
  //    after each pass so neighbours coalesce. This is what makes two adjacent
  //    fast splits with no real recovery read as ONE rep.
  const reclass = (drop: Segment, minSec: number) => {
    for (const r of runs) {
      if (r.seg === drop && durOf(r) < minSec) {
        r.seg = drop === "recovery" ? "work" : "recovery";
      }
    }
    // re-merge
    const merged: Run[] = [];
    for (const r of runs) {
      const last = merged[merged.length - 1];
      if (last && last.seg === r.seg) last.hi = r.hi;
      else merged.push({ ...r });
    }
    runs.length = 0;
    runs.push(...merged);
  };
  reclass("recovery", o.minRecoverySec);
  reclass("work", o.minWorkSec);

  // 4) Emit chronological bouts + recoveries.
  const segments: BoutOrRecovery[] = [];
  let boutIdx = 0;
  for (const r of runs) {
    const start_s = time[r.lo];
    const end_s = time[r.hi];
    const duration_s = Math.max(0, end_s - start_s);
    const start_m = dist[r.lo];
    const end_m = dist[r.hi];
    const distance_m = Math.max(0, end_m - start_m);
    const avg_vel_ms = duration_s > 0 ? distance_m / duration_s : 0;

    if (r.seg === "work") {
      boutIdx += 1;
      const secPerMile = avg_vel_ms > 0 ? 1609.34 / avg_vel_ms : 0;
      const secPerKm = avg_vel_ms > 0 ? 1000 / avg_vel_ms : 0;
      segments.push({
        kind: "work",
        index: boutIdx,
        start_s, end_s, duration_s,
        start_m: Math.round(start_m), end_m: Math.round(end_m),
        distance_m: Math.round(distance_m),
        avg_vel_ms: Math.round(avg_vel_ms * 100) / 100,
        avg_pace_per_mile: pace(secPerMile),
        avg_pace_per_km: pace(secPerKm),
      });
    } else {
      // Don't emit a leading/trailing recovery before any work has happened.
      if (boutIdx === 0) continue;
      segments.push({
        kind: "recovery",
        after_bout: boutIdx,
        duration_s,
        distance_m: Math.round(distance_m),
        avg_vel_ms: Math.round(avg_vel_ms * 100) / 100,
        style: avg_vel_ms < o.standingVelMs ? "standing" : "jog",
      });
    }
  }

  // Trim a trailing recovery (cooldown handled separately; a rest with no rep
  // after it isn't a separator).
  while (segments.length && segments[segments.length - 1].kind === "recovery") {
    segments.pop();
  }

  return { segments, workVelMs: Math.round(workVel * 100) / 100 };
}

/**
 * A watch lap, as it arrives in `external_streams.laps` (Strava lap shape). Only
 * the fields the segmenter needs are typed; everything else is ignored.
 */
export interface LapInput {
  distance?: number;         // meters
  moving_time?: number;      // seconds
  elapsed_time?: number;     // seconds
  average_speed?: number;    // m/s
  average_heartrate?: number;
  start_index?: number;      // index into the per-second streams
  end_index?: number;
  lap_index?: number;
}

/**
 * Segment a run into recovery-bounded work bouts FROM THE ATHLETE'S OWN WATCH
 * LAPS, instead of re-deriving boundaries from the noisy per-second GPS trace.
 *
 * Same core rule as detectWorkBouts — a rep is bounded by a recovery, not a
 * distance marker — but applied at lap granularity. When an athlete runs a
 * structured session, their watch records each rep and each recovery as its own
 * lap, and those boundaries are crisp: exact distance and moving-time, no
 * acceleration/deceleration smear, no warmup-jog bleeding into the first hard
 * effort. Consecutive same-class laps merge (three 1 km tempo laps become one
 * 3 km bout; a rep flanked by jog laps stays one rep), so the output shape is
 * identical to detectWorkBouts and drops straight into blocksFromBouts.
 *
 * This is deliberately NOT "trust the lap markers" — auto-lap-by-distance lies
 * exactly as the module header warns. It's "trust the athlete's fast/slow
 * ALTERNATION": the caller only prefers this over the GPS pass when it yields a
 * real structure (>= 2 work bouts), which only happens when the laps genuinely
 * encode reps-and-recoveries. A steady run auto-lapped every mile collapses to a
 * single bout and the caller falls back to the GPS segmenter.
 *
 * `streams` is optional and used only to resolve each bout's real time window
 * (via lap start/end indices) so downstream HR averaging lines up; without it,
 * windows fall back to cumulative moving time.
 */
export function boutsFromLaps(
  laps: LapInput[],
  streams?: RawStreams,
  opts: DetectOptions = {},
): { segments: BoutOrRecovery[]; workVelMs: number } {
  const o = { ...DEFAULTS, ...opts };
  if (!Array.isArray(laps) || laps.length < 2) return { segments: [], workVelMs: 0 };

  const norm = laps
    .map((l) => {
      const dist_m = Number(l.distance ?? 0);
      const dur_s = Number(l.moving_time ?? l.elapsed_time ?? 0);
      const declaredVel = Number(l.average_speed ?? 0);
      const vel = declaredVel > 0 ? declaredVel : dur_s > 0 ? dist_m / dur_s : 0;
      return { dist_m, dur_s, vel, start_index: l.start_index, end_index: l.end_index };
    })
    .filter((l) =>
      l.dist_m > 0 && l.dur_s > 0 && isFinite(l.vel) &&
      !(l.dist_m < FRAGMENT_MAX_METERS && l.dur_s < FRAGMENT_MAX_SECONDS)
    );

  if (norm.length < 2) return { segments: [], workVelMs: 0 };

  // Work-velocity baseline = median of the fast cluster. Anchor on a high
  // percentile of lap speed so a session with MORE recovery laps than work laps
  // can't drag the baseline down into the recovery band.
  const moving = norm.map((l) => l.vel).filter((v) => v > o.standingVelMs);
  if (moving.length === 0) return { segments: [], workVelMs: 0 };
  const sortedVel = [...moving].sort((a, b) => a - b);
  const anchor = sortedVel[Math.min(sortedVel.length - 1, Math.floor(sortedVel.length * 0.9))];
  const fastCluster = norm.filter((l) => l.vel >= 0.7 * anchor).map((l) => l.vel);
  const workVel = median(fastCluster.length ? fastCluster : moving);
  if (workVel <= 0) return { segments: [], workVelMs: 0 };

  // Prefer the adaptive bimodal boundary — it separates the fast reps from
  // easy-but-not-slow recovery jogs that the fixed 0.7 fraction wrongly counts
  // as work. Fall back to the fixed fraction when the laps aren't clearly two-
  // clustered (steady runs, smooth progressions), leaving those unchanged.
  const adaptiveBoundary = bimodalWorkRecoveryBoundary(
    norm.map((l) => l.vel),
    o.standingVelMs,
  );
  const recoveryThreshold = adaptiveBoundary ?? o.recoveryFrac * workVel;

  const cls: Segment[] = norm.map((l) => (l.vel < recoveryThreshold ? "recovery" : "work"));

  // Merge consecutive same-class laps.
  type Group = { seg: Segment; laps: typeof norm };
  const groups: Group[] = [];
  norm.forEach((l, i) => {
    const last = groups[groups.length - 1];
    if (last && last.seg === cls[i]) last.laps.push(l);
    else groups.push({ seg: cls[i], laps: [l] });
  });

  const time = streams?.time ?? [];
  const tAt = (idx?: number) => (idx != null && idx >= 0 && idx < time.length ? time[idx] : undefined);

  const segments: BoutOrRecovery[] = [];
  let boutIdx = 0;
  let cumDist = 0; // cumulative meters across ALL laps (for start_m/end_m)
  let clockS = 0;  // fallback cumulative time when stream indices are absent
  for (const g of groups) {
    const dist_m = g.laps.reduce((a, b) => a + b.dist_m, 0);
    const dur_s = g.laps.reduce((a, b) => a + b.dur_s, 0);
    const avg_vel_ms = dur_s > 0 ? dist_m / dur_s : 0;
    const start_m = cumDist;
    const end_m = cumDist + dist_m;
    cumDist = end_m;
    const start_s = tAt(g.laps[0].start_index) ?? clockS;
    const end_s = tAt(g.laps[g.laps.length - 1].end_index) ?? start_s + dur_s;
    clockS = end_s;

    if (g.seg === "work") {
      boutIdx += 1;
      const secPerMile = avg_vel_ms > 0 ? 1609.34 / avg_vel_ms : 0;
      const secPerKm = avg_vel_ms > 0 ? 1000 / avg_vel_ms : 0;
      segments.push({
        kind: "work",
        index: boutIdx,
        start_s, end_s, duration_s: dur_s,
        start_m: Math.round(start_m), end_m: Math.round(end_m),
        distance_m: Math.round(dist_m),
        avg_vel_ms: Math.round(avg_vel_ms * 100) / 100,
        avg_pace_per_mile: pace(secPerMile),
        avg_pace_per_km: pace(secPerKm),
      });
    } else {
      // A recovery before any work is a warmup, not a separator — skip it.
      if (boutIdx === 0) continue;
      segments.push({
        kind: "recovery",
        after_bout: boutIdx,
        duration_s: dur_s,
        distance_m: Math.round(dist_m),
        avg_vel_ms: Math.round(avg_vel_ms * 100) / 100,
        style: avg_vel_ms < o.standingVelMs ? "standing" : "jog",
      });
    }
  }

  // Trim a trailing recovery/cooldown — a rest with no rep after it isn't a
  // separator (mirrors detectWorkBouts).
  while (segments.length && segments[segments.length - 1].kind === "recovery") {
    segments.pop();
  }

  return { segments, workVelMs: Math.round(workVel * 100) / 100 };
}

/** Count the work bouts in a segment list (caller's reliability gate). */
export function workBoutCount(segments: BoutOrRecovery[]): number {
  return segments.reduce((n, s) => (s.kind === "work" ? n + 1 : n), 0);
}

/** Parse "M:SS" → sec/mile, or null. */
function parsePaceStr(p: string | null | undefined): number | null {
  if (!p) return null;
  const m = String(p).trim().match(/^(\d{1,2}):(\d{2})$/);
  if (!m) return null;
  const s = parseInt(m[1], 10) * 60 + parseInt(m[2], 10);
  return s > 0 ? s : null;
}

/** A block of a corrected `parsed_structure` (from correct-workout-structure). */
export interface ParsedBlock {
  role?: string;               // warmup | work_rep | recovery | cooldown
  is_rest?: boolean;
  distance_miles?: number;
  distance_meters?: number;
  duration_s?: number;
  moving_time_seconds?: number;
  avg_pace_per_mile?: string | null;
  avg_pace_sec_per_mile?: number | null;
  avg_hr?: number | null;
}

/** A lap row in the shape `segmentFromLaps` consumes (subset of running_workout_laps). */
export interface StructureLap {
  lap_index: number;
  is_rest: boolean;
  distance_meters: number;
  moving_time_seconds: number;
  elapsed_time_seconds: number;
  avg_pace_sec_per_mile: number | null;
  avg_heart_rate: number | null;
}

/**
 * Convert a corrected `parsed_structure` into lap rows, so a session the athlete
 * has FIXED drives the same lap-based surfaces (key sessions, the pace ladder,
 * quality volume) as native/derived laps — the athlete's correction is the
 * verdict. Each block becomes one lap; `work_rep` is work, everything else
 * (warmup / recovery / cooldown) is a rest hint. Pace is preserved so
 * `segmentFromLaps` classifies each lap to the athlete's zones.
 *
 * Returns [] when the structure has no usable blocks (caller keeps the existing
 * laps).
 */
export function lapsFromParsedStructure(parsed: unknown): StructureLap[] {
  const blocks = (parsed as { blocks?: ParsedBlock[] } | null)?.blocks;
  if (!Array.isArray(blocks) || blocks.length === 0) return [];
  const out: StructureLap[] = [];
  let idx = 0;
  for (const b of blocks) {
    const dm = b.distance_meters ?? (b.distance_miles != null ? b.distance_miles * 1609.34 : 0);
    if (!(dm > 0)) continue;
    const secs = Math.round(b.duration_s ?? b.moving_time_seconds ?? 0);
    const paceSec = b.avg_pace_sec_per_mile ?? parsePaceStr(b.avg_pace_per_mile) ??
      (secs > 0 ? Math.round(secs / (dm / 1609.34)) : null);
    const isRest = b.is_rest ?? (b.role ? b.role !== "work_rep" : false);
    out.push({
      lap_index: idx++,
      is_rest: isRest,
      distance_meters: Math.round(dm),
      moving_time_seconds: secs,
      elapsed_time_seconds: secs,
      avg_pace_sec_per_mile: paceSec,
      avg_heart_rate: b.avg_hr ?? null,
    });
  }
  return out;
}

/**
 * A lap row in the Strava `external_streams.laps` shape, derived from the
 * per-second stream. Written when a provider (Garmin via Junction/Vital) gives
 * us the stream but NO native laps — so the existing lap trigger + all the
 * lap-based analytics (segmentFromLaps → key sessions → the pace ladder) keep
 * working. See `derivedLapsFromStream`.
 */
export interface DerivedLap {
  lap_index: number;
  distance: number;          // meters
  moving_time: number;       // seconds
  elapsed_time: number;      // seconds
  average_speed: number;     // m/s
  average_heartrate: number | null;
  max_heartrate: number | null;
  start_index: number | null;
  end_index: number | null;
  /** Recovery hint. `segmentFromLaps` treats pace as truth, but we set it. */
  is_rest: boolean;
}

/** Nearest stream index for a time value (time[] is monotonic). */
function indexAtTime(time: number[], t: number): number | null {
  const n = time.length;
  if (n === 0) return null;
  let lo = 0, hi = n - 1;
  if (t <= time[0]) return 0;
  if (t >= time[n - 1]) return n - 1;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (time[mid] < t) lo = mid + 1; else hi = mid;
  }
  // lo is the first index with time[lo] >= t; pick the closer neighbour.
  if (lo > 0 && Math.abs(time[lo - 1] - t) <= Math.abs(time[lo] - t)) return lo - 1;
  return lo;
}

/** Mean + max HR over a stream window [i0, i1] (skips zeros). */
function hrOverWindow(hr: number[], i0: number | null, i1: number | null): { avg: number | null; max: number | null } {
  if (i0 == null || i1 == null || hr.length === 0) return { avg: null, max: null };
  const lo = Math.max(0, Math.min(i0, i1));
  const hi = Math.min(hr.length - 1, Math.max(i0, i1));
  let sum = 0, cnt = 0, mx = 0;
  for (let i = lo; i <= hi; i++) {
    const h = hr[i];
    if (h && h > 0) { sum += h; cnt += 1; if (h > mx) mx = h; }
  }
  return cnt > 0 ? { avg: Math.round(sum / cnt), max: mx } : { avg: null, max: null };
}

/**
 * Derive rep-level laps from the per-second stream, in the Strava lap shape the
 * `sync_workout_laps_from_streams` trigger consumes.
 *
 * Reuses the tested `detectWorkBouts` (recovery-bounded, bimodal-boundary
 * detection) so the derived reps match exactly what the parser sees — no second
 * detector to drift. Each work bout and each recovery between reps becomes one
 * lap; a recovery's time window is bounded by the surrounding work bouts (the
 * `Recovery` shape carries duration/distance but not its own clock, and
 * `detectWorkBouts` trims leading/trailing recoveries, so every recovery sits
 * between two bouts). HR is averaged from the stream over each window.
 *
 * Returns [] when nothing segments (a steady run, or no usable stream) — the
 * caller then simply writes no laps, and the surface degrades honestly.
 */
export function derivedLapsFromStream(
  streams: RawStreams & { heartrate?: number[] },
  opts: DetectOptions = {},
): DerivedLap[] {
  const { segments } = detectWorkBouts(streams, opts);
  if (segments.length === 0) return [];

  const time = streams.time ?? [];
  const hr = streams.heartrate ?? [];

  // Work-bout clock windows, keyed by bout index, to place the recoveries.
  const workWindow = new Map<number, { start_s: number; end_s: number }>();
  for (const s of segments) {
    if (s.kind === "work") workWindow.set(s.index, { start_s: s.start_s, end_s: s.end_s });
  }

  const laps: DerivedLap[] = [];
  let lapIndex = 0;
  for (const s of segments) {
    if (s.kind === "work") {
      const i0 = indexAtTime(time, s.start_s);
      const i1 = indexAtTime(time, s.end_s);
      const { avg, max } = hrOverWindow(hr, i0, i1);
      laps.push({
        lap_index: lapIndex++,
        distance: s.distance_m,
        moving_time: Math.round(s.duration_s),
        elapsed_time: Math.round(s.duration_s),
        average_speed: s.avg_vel_ms,
        average_heartrate: avg,
        max_heartrate: max,
        start_index: i0,
        end_index: i1,
        is_rest: false,
      });
    } else {
      // Recovery window = [end of the bout it follows, start of the next bout].
      const prev = workWindow.get(s.after_bout);
      const next = workWindow.get(s.after_bout + 1);
      const start_s = prev?.end_s ?? 0;
      const end_s = next?.start_s ?? (start_s + s.duration_s);
      const i0 = indexAtTime(time, start_s);
      const i1 = indexAtTime(time, end_s);
      const { avg, max } = hrOverWindow(hr, i0, i1);
      laps.push({
        lap_index: lapIndex++,
        distance: s.distance_m,
        moving_time: Math.round(s.duration_s),
        elapsed_time: Math.round(s.duration_s),
        average_speed: s.avg_vel_ms,
        average_heartrate: avg,
        max_heartrate: max,
        start_index: i0,
        end_index: i1,
        is_rest: true,
      });
    }
  }
  return laps;
}

export type LapRole = "warmup" | "rep" | "recovery" | "cooldown";

/**
 * Per-lap DESCRIPTIVE label for the splits view.
 *
 * The splits chart lists every lap the watch recorded, exactly as recorded —
 * this only TAGS each row (warmup / rep / recovery / cooldown) so the athlete
 * can read the structure. It NEVER merges, drops, re-orders, or re-paces a lap,
 * and it is not `is_rest`: the split's distance/pace/HR are always the watch's
 * own numbers. A lap is a "rep" when it clears the same velocity work/recovery
 * boundary `boutsFromLaps` uses; the easy laps before the first rep are
 * "warmup", after the last are "cooldown", and easy laps between reps are
 * "recovery". Keyed by the lap's own `lap_index` so the client joins 1:1.
 */
export function lapRoles(laps: LapInput[]): Array<{ lap_index: number; role: LapRole }> {
  if (!Array.isArray(laps) || laps.length === 0) return [];
  const o = DEFAULTS;

  const rows = laps.map((l, i) => {
    const dist_m = Number(l.distance ?? 0);
    const dur_s = Number(l.moving_time ?? l.elapsed_time ?? 0);
    const declaredVel = Number(l.average_speed ?? 0);
    const vel = declaredVel > 0 ? declaredVel : dur_s > 0 ? dist_m / dur_s : 0;
    const lap_index = l.lap_index ?? i;
    // A lap short in BOTH distance and duration is a GPS artifact, not a rep.
    const isFragment = dist_m < FRAGMENT_MAX_METERS && dur_s < FRAGMENT_MAX_SECONDS;
    const valid = dist_m > 0 && dur_s > 0 && isFinite(vel);
    return { lap_index, vel, valid, isFragment };
  });

  // Work-velocity boundary from the non-fragment laps — the SAME basis as
  // boutsFromLaps, so the labels agree with the detected structure.
  const normVels = rows.filter((r) => r.valid && !r.isFragment).map((r) => r.vel);
  if (normVels.length < 2) {
    // Too little to separate reps from rest — don't guess; call each valid lap a
    // rep (the list still shows every lap regardless of label).
    return rows.map((r) => ({ lap_index: r.lap_index, role: "rep" as LapRole }));
  }
  const moving = normVels.filter((v) => v > o.standingVelMs);
  const sortedVel = [...moving].sort((a, b) => a - b);
  const anchor = sortedVel[Math.min(sortedVel.length - 1, Math.floor(sortedVel.length * 0.9))];
  const fastCluster = normVels.filter((v) => v >= 0.7 * anchor);
  const workVel = median(fastCluster.length ? fastCluster : moving);
  const adaptiveBoundary = bimodalWorkRecoveryBoundary(normVels, o.standingVelMs);
  const recoveryThreshold = adaptiveBoundary ?? o.recoveryFrac * workVel;

  const isWork = rows.map((r) => r.valid && !r.isFragment && r.vel >= recoveryThreshold);
  const firstWork = isWork.indexOf(true);
  const lastWork = isWork.lastIndexOf(true);

  return rows.map((r, i) => {
    let role: LapRole;
    if (isWork[i]) role = "rep";
    else if (firstWork < 0 || i < firstWork) role = "warmup";
    else if (i > lastWork) role = "cooldown";
    else role = "recovery";
    return { lap_index: r.lap_index, role };
  });
}

/**
 * Render detected bouts as a compact, model-readable block for the parser
 * prompt. Empty string when nothing was detected (caller substitutes "(none)").
 */
export function formatWorkBouts(segments: BoutOrRecovery[]): string {
  if (segments.length === 0) return "";
  const lines: string[] = [];
  for (const s of segments) {
    if (s.kind === "work") {
      const km = (s.distance_m / 1000).toFixed(2);
      const mi = (s.distance_m / 1609.34).toFixed(2);
      const dur = `${Math.floor(s.duration_s / 60)}:${String(Math.round(s.duration_s % 60)).padStart(2, "0")}`;
      const near = nearestRepDistance(s.distance_m);
      const tnear = nearestTimeRep(s.duration_s);
      const distSnap = near.label
        ? `${near.label}${near.ambiguous ? "(±)" : ""}`
        : "ragged";
      const timeSnap = tnear.label
        ? `${tnear.label}${tnear.ambiguous ? "(±)" : ""}`
        : "ragged";
      lines.push(
        `Bout ${s.index}: ${km} km / ${mi} mi in ${dur} @ ${s.avg_pace_per_km}/km (${s.avg_pace_per_mile}/mi) — by distance ≈ ${distSnap}, by time ≈ ${timeSnap}`,
      );
    } else {
      const mmss = `${Math.floor(s.duration_s / 60)}:${String(Math.round(s.duration_s % 60)).padStart(2, "0")}`;
      lines.push(`  ↳ recovery: ${mmss} ${s.style}`);
    }
  }
  return lines.join("\n");
}

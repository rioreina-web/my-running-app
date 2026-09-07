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
  /** MOVING seconds — watch-stopped gaps inside the bout are excluded. */
  duration_s: number;
  /** Seconds the recording was stopped inside this bout (0 when it ran clean). */
  stopped_s: number;
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
  /** MOVING seconds — watch-stopped gaps are excluded, standing rests are not. */
  duration_s: number;
  /** Seconds the recording was stopped inside this recovery. */
  stopped_s: number;
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

// ── Stopped-watch gaps ──────────────────────────────────────────────────────
// When the athlete stops the watch (or auto-pause fires), the recording simply
// SKIPS those seconds: `time` jumps 3000 → 3400 between two adjacent samples
// while `distance` barely moves. That gap is one sample-to-sample step, so its
// measured span (`time[hi] − time[lo]` over a single index) is 0 — it slips
// under `minRecoverySec`, gets reclassed as running, and its minutes are then
// swallowed by the enclosing bout's `end_s − start_s`. An 18-miler with 12 such
// stops read 7:20/mi instead of its true 6:38/mi (2026-08-08).
//
// So bout duration is the SUM of per-sample steps with stop-gaps discounted,
// never the raw clock span. Two guards keep this honest:

/** A step longer than this isn't a slow second of running — it's a break in
 *  the recording. (Streams are ~1 Hz; Strava thins to a few seconds at most.) */
export const MAX_SAMPLE_STEP_SEC = 5;

/** …but a break only counts as STOPPED when almost no ground was covered
 *  across it. A tunnel/canyon dropout while running still advances distance at
 *  running speed, and that time is real — it must keep counting. */
export const STOPPED_GAP_VEL_MS = 0.5;

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
 * Options shared by the two boundary finders. `durations` lets the alternation
 * gate reason in SECONDS (per-sample steps for the stream path, lap moving-time
 * for the lap path) instead of counting array slots.
 */
export interface BoundaryOptions {
  durations?: number[];
  minWorkSec?: number;
  minRecoverySec?: number;
}

/**
 * Does a candidate work/recovery boundary describe a WORKOUT — or is it just a
 * line drawn through a run that never actually alternated?
 *
 * This is the gate that stops the parser inventing structure. A boundary is only
 * believable when the run crosses it back and forth the way a session does:
 * at least TWO efforts long enough to be reps, with a real recovery between
 * them. A steady run, a progression, and a long climb all have a velocity
 * distribution you *can* cut in two — but cutting them yields one work stretch
 * with easy running on one side, never an alternation, so every candidate fails
 * and the caller keeps its conservative fallback.
 *
 * Runs on the ORDERED velocities (time order), which is exactly what the
 * distribution-only view throws away.
 */
function alternatesLikeAWorkout(
  vels: number[],
  durations: number[],
  boundary: number,
  minWorkSec: number,
  minRecoverySec: number,
): boolean {
  type Run = { work: boolean; secs: number };
  const runs: Run[] = [];
  for (let i = 0; i < vels.length; i++) {
    const work = vels[i] >= boundary;
    const secs = durations[i] ?? 0;
    const last = runs[runs.length - 1];
    if (last && last.work === work) last.secs += secs;
    else runs.push({ work, secs });
  }

  let reps = 0;
  let separators = 0;
  let restSinceLastRep = 0;
  for (const r of runs) {
    if (r.work) {
      if (r.secs < minWorkSec) continue; // a blip, not a rep
      if (reps === 0) reps = 1;
      else if (restSinceLastRep >= minRecoverySec) {
        reps += 1;
        separators += 1;
      }
      restSinceLastRep = 0;
    } else if (r.secs >= minRecoverySec) {
      restSinceLastRep += r.secs;
    }
  }
  return reps >= 2 && separators >= 1;
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
 * laps by looking for a clear empty band in the lap velocities, and only trust it
 * when the two groups are genuinely separated: the band must be much wider than
 * the spacing *within* either group, the fast group must be meaningfully faster,
 * AND the run must actually alternate across the band like a workout. A steady
 * run (one cluster) or a smooth progression (evenly spaced, no band) fails those
 * guards and returns null, so the caller keeps the fixed-fraction fallback and
 * those sessions behave exactly as before.
 *
 * WHY EVERY BAND IS TRIED, not just the widest one (fixed 2026-08-14):
 * this used to pick the single split that best separated the laps (Otsu). On a
 * real session that split is almost never rep-vs-recovery — it is
 * WARMUP/COOLDOWN vs THE WORKOUT, because an 8:00/mi warmup is further from a
 * 5:30 rep than the 6:15 jog recovery is. The boundary landed below the jog
 * recoveries, so every rep and every recovery classed as "work" and merged into
 * one fabricated split ("7.24 mi @ 5:38/mi" — a pace the athlete never ran at
 * for a step). Scanning every band and keeping only those that produce a real
 * alternation kills that: the warmup band leaves the reps and recoveries in one
 * unbroken work stretch, which is not a workout shape, so it is rejected and
 * the rep/recovery band wins.
 *
 * Returns the boundary velocity (m/s) — laps below it are recovery — or null when
 * the laps aren't clearly two-clustered.
 */
export function bimodalWorkRecoveryBoundary(
  vels: number[],
  standingVelMs: number,
  opts: BoundaryOptions = {},
): number | null {
  const durations = opts.durations ?? vels.map(() => 60);
  const minWorkSec = opts.minWorkSec ?? DEFAULTS.minWorkSec;
  const minRecoverySec = opts.minRecoverySec ?? DEFAULTS.minRecoverySec;

  // Ignore near-standing points so a lone stop/cooldown fragment can't hijack
  // the split — the two clusters we're separating are the running laps.
  const v = vels.filter((x) => x > standingVelMs).sort((a, b) => a - b);
  if (v.length < 4) return null;

  let best: number | null = null;
  let bestScore = -1;

  for (let k = 0; k < v.length - 1; k++) {
    const band = v[k + 1] - v[k];
    if (band <= 0) continue; // identical laps — no band to split on

    const low = v.slice(0, k + 1);
    const high = v.slice(k + 1);
    const muLow = low.reduce((a, b) => a + b, 0) / low.length;
    const muHigh = high.reduce((a, b) => a + b, 0) / high.length;

    // Guard 1: the fast group must be meaningfully faster than the slow group.
    // Rejects a steady run (one cluster split down the middle → ratio ≈ 1).
    if (muLow <= 0 || muHigh / muLow < 1.1) continue;

    // Guard 2: a real empty band between the groups. The gap that separates them
    // must dwarf the typical spacing WITHIN the groups — otherwise the data is a
    // smooth continuum (a progression), not two distinct efforts.
    const innerGaps: number[] = [];
    for (let i = 1; i < low.length; i++) innerGaps.push(low[i] - low[i - 1]);
    for (let i = 1; i < high.length; i++) innerGaps.push(high[i] - high[i - 1]);
    const meanInner = innerGaps.length
      ? innerGaps.reduce((a, b) => a + b, 0) / innerGaps.length
      : 0;
    if (meanInner > 0 && band < 2.5 * meanInner) continue;

    const boundary = (v[k] + v[k + 1]) / 2;

    // Guard 3: the session must actually cross this boundary like a workout.
    if (!alternatesLikeAWorkout(vels, durations, boundary, minWorkSec, minRecoverySec)) {
      continue;
    }

    // Among the believable bands, keep the cleanest separation.
    const score = meanInner > 0 ? band / meanInner : band;
    if (score > bestScore) {
      bestScore = score;
      best = boundary;
    }
  }

  return best;
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
 * Deliberately conservative — a steady run (one peak), a smooth progression, and
 * a standing-rest interval session (the rests are below `standingVelMs` and never
 * enter the histogram) all return null, so the caller keeps the exact
 * fixed-fraction fallback and their behavior is unchanged. Only sessions that
 * genuinely alternate between two speeds get a corrected boundary.
 *
 * TWO BUGS FIXED HERE (2026-08-14) — both made this return null on real data,
 * which sent every session to the 0.7×median fallback that merges reps and jog
 * recoveries into one invented split:
 *
 *  1. The old "reject a multi-modal continuum" guard compared the two MODE BINS
 *     against the tallest bin outside them. But a real cluster has width: the
 *     rep peak's own shoulder bins sit outside [mode1, mode2] and are nearly as
 *     tall as the peak itself, so the guard fired on essentially every noisy
 *     (i.e. every real) stream. Clusters are now walked out to their edges, so
 *     a peak's own shoulders can no longer masquerade as a third cluster.
 *  2. Only the two TALLEST modes were considered. A full session is usually
 *     three-clustered — warmup/cooldown, jog recoveries, reps — and the two
 *     tallest are often warmup and reps, with the recovery cluster sitting in
 *     the middle filling the valley. The valleys are now tried from the FASTEST
 *     cluster downwards, so the rep/recovery boundary is found first, and each
 *     candidate must pass the alternation gate before it's accepted.
 */
export function bimodalBoundaryFromDensity(
  vels: number[],
  standingVelMs: number,
  opts: BoundaryOptions = {},
): number | null {
  const durations = opts.durations ?? vels.map(() => 1);
  const minWorkSec = opts.minWorkSec ?? DEFAULTS.minWorkSec;
  const minRecoverySec = opts.minRecoverySec ?? DEFAULTS.minRecoverySec;
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

  // ── Find every speed cluster, not just the two tallest ──
  // A candidate mode is a local maximum carrying real mass. Two candidates are
  // the SAME cluster unless a genuine trough separates them (the peak's own
  // shoulders are part of it), in which case only the taller survives.
  let globalMax = 0;
  for (let i = 0; i < BINS; i++) if (sm[i] > globalMax) globalMax = sm[i];
  if (globalMax <= 0) return null;

  const candidates: number[] = [];
  for (let i = 0; i < BINS; i++) {
    const left = i > 0 ? sm[i - 1] : -1;
    const right = i < BINS - 1 ? sm[i + 1] : -1;
    if (sm[i] >= left && sm[i] >= right && sm[i] >= 0.15 * globalMax) candidates.push(i);
  }

  const modes: number[] = [];
  for (const p of candidates) {
    const prev = modes[modes.length - 1];
    if (prev === undefined) {
      modes.push(p);
      continue;
    }
    let trough = Infinity;
    for (let i = prev + 1; i < p; i++) if (sm[i] < trough) trough = sm[i];
    const smallerPeak = Math.min(sm[prev], sm[p]);
    const separated = p - prev >= 2 && trough < 0.5 * smallerPeak;
    if (separated) modes.push(p);
    else if (sm[p] > sm[prev]) modes[modes.length - 1] = p; // same cluster
  }
  if (modes.length < 2) return null;

  // ── Try the valley below the FASTEST cluster first, then work downwards ──
  // On a full session the fastest cluster is the reps; the one below it is the
  // jog recoveries; below that, the warmup/cooldown. The rep/recovery line is
  // the one we want, and it is always the topmost valley that alternates.
  const SEP = Math.max(2, Math.round(BINS * 0.15));
  for (let k = modes.length - 1; k > 0; k--) {
    const hiMode = modes[k];
    const loMode = modes[k - 1];
    if (hiMode - loMode < SEP) continue; // modes too close → not two efforts

    let minC = Infinity;
    for (let i = loMode + 1; i < hiMode; i++) if (sm[i] < minC) minC = sm[i];
    const valleyBins: number[] = [];
    for (let i = loMode + 1; i < hiMode; i++) if (sm[i] === minC) valleyBins.push(i);
    if (valleyBins.length === 0) continue;
    const valley = valleyBins[Math.floor(valleyBins.length / 2)];
    const boundary = lo + (valley + 0.5) * width;

    // The run must actually cross this line like a workout — repeatedly, with
    // real recoveries. A progression can be cut anywhere and never passes.
    if (alternatesLikeAWorkout(vels, durations, boundary, minWorkSec, minRecoverySec)) {
      return boundary;
    }
  }

  return null;
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

  // ── Active seconds per sample (stop-gaps discounted) ──
  // step[i] is the time the interval (i−1, i] contributes to a bout's duration.
  // A stopped-watch gap contributes only the stream's nominal sample step; the
  // rest of it never happened as running and must not dilute the pace.
  const rawSteps: number[] = [];
  for (let i = 1; i < n; i++) {
    const dt = time[i] - time[i - 1];
    if (dt > 0) rawSteps.push(dt);
  }
  const nominalStep = rawSteps.length ? median(rawSteps) : 1;
  const step = new Array<number>(n).fill(0);
  for (let i = 1; i < n; i++) {
    const dt = time[i] - time[i - 1];
    if (!(dt > 0)) { step[i] = 0; continue; }
    const gapVel = (dist[i] - dist[i - 1]) / dt;
    const stopped = dt > MAX_SAMPLE_STEP_SEC && gapVel < STOPPED_GAP_VEL_MS;
    step[i] = stopped ? Math.min(dt, nominalStep) : dt;
  }
  /** Moving seconds between two sample indices (stop-gaps excluded). */
  const activeBetween = (lo: number, hi: number): number => {
    let s = 0;
    for (let i = lo + 1; i <= hi; i++) s += step[i];
    return s;
  };

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
  const densityBoundary = bimodalBoundaryFromDensity(vel.slice(0, n), o.standingVelMs, {
    durations: step.slice(0, n),
    minWorkSec: o.minWorkSec,
    minRecoverySec: o.minRecoverySec,
  });
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

  // Moving duration, not clock span — a run whose only "length" is a stopped
  // watch must read as 0s here so it can't survive the minRecoverySec filter.
  const durOf = (r: Run) => activeBetween(r.lo, r.hi);

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
    // Pace is distance over MOVING time. `end_s − start_s` is the wall clock,
    // which includes every second the watch spent stopped inside this run.
    const duration_s = Math.max(0, activeBetween(r.lo, r.hi));
    const stopped_s = Math.max(0, Math.round((end_s - start_s) - duration_s));
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
        start_s, end_s, duration_s, stopped_s,
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
        duration_s, stopped_s,
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
      // The watch already tells us how long it sat stopped in this lap.
      const stop_s = Math.max(0, Number(l.elapsed_time ?? dur_s) - dur_s);
      const declaredVel = Number(l.average_speed ?? 0);
      const vel = declaredVel > 0 ? declaredVel : dur_s > 0 ? dist_m / dur_s : 0;
      return { dist_m, dur_s, stop_s, vel, start_index: l.start_index, end_index: l.end_index };
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
    {
      durations: norm.map((l) => l.dur_s),
      minWorkSec: o.minWorkSec,
      minRecoverySec: o.minRecoverySec,
    },
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
    const stopped_s = Math.round(g.laps.reduce((a, b) => a + b.stop_s, 0));
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
        start_s, end_s, duration_s: dur_s, stopped_s,
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
        duration_s: dur_s, stopped_s,
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

/**
 * Does this segmentation describe a session with FAST and EASY running in it —
 * or just one steady pace, interrupted?
 *
 * THE TRAFFIC-LIGHT CASE (2026-08-14). Waiting at a light on an easy run leaves
 * a minute of near-zero velocity in the stream — which looks exactly like a
 * standing rest between two reps. The GPS pass duly split an easy 8-miler into
 * "4 reps @ 8:00/mi", and because that beat the athlete's own steady mile laps
 * on bout COUNT, it overrode them. The run was never a workout and the laps
 * always said so.
 *
 * (Only when the watch is left RUNNING at the light. Actually stopping the
 * watch leaves a time gap, which the stop-gap logic above already discounts —
 * those runs were never affected.)
 *
 * The test: a real session has speed contrast. Either the reps are meaningfully
 * faster than the moving recoveries between them, or they are meaningfully
 * faster than the run's own average pace. A blurred workout — the case this
 * override exists for, where the watch auto-lapped by distance and averaged the
 * reps and recoveries into flat splits — always clears one of those, because
 * there were genuinely two speeds in the run. A steady run with stops clears
 * neither: every "rep" is the same pace as the run as a whole.
 *
 * `activityAvgVelMs` is the whole run's average moving velocity (m/s) — pass 0
 * when it isn't known and only the recovery-contrast test applies.
 */
export function structureHasSpeedContrast(
  segments: BoutOrRecovery[],
  activityAvgVelMs = 0,
  minRatio = 1.15,
): boolean {
  const work = segments.filter((s): s is WorkBout => s.kind === "work");
  if (work.length < 2) return false;
  const workVel = median(work.map((s) => s.avg_vel_ms).filter((v) => v > 0));
  if (!(workVel > 0)) return false;

  // Reps meaningfully faster than the jog recoveries they alternate with.
  const jogs = segments.filter(
    (s): s is Recovery => s.kind === "recovery" && s.style === "jog" && s.avg_vel_ms > 0,
  );
  if (jogs.length > 0 && workVel / median(jogs.map((s) => s.avg_vel_ms)) >= minRatio) {
    return true;
  }

  // …or meaningfully faster than the run's own average. This is what catches a
  // genuine session whose rests were STANDING (a track workout the watch
  // auto-lapped by mile): its reps still tower over the run average, because
  // the warmup, the rests and the cooldown all drag that average down.
  return activityAvgVelMs > 0 && workVel / activityAvgVelMs >= minRatio;
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

  // No speed contrast → this is one continuous effort that happened to be
  // interrupted (a traffic light, a road crossing), not a set of reps. Writing
  // the "reps" out as laps would put a fabricated workout into every
  // lap-driven surface — key sessions, the pace ladder, quality volume.
  const totalM = segments.reduce((a, s) => a + s.distance_m, 0);
  const totalS = segments.reduce((a, s) => a + s.duration_s, 0);
  const activityAvgVel = totalS > 0 ? totalM / totalS : 0;
  const workBouts = segments.filter((s): s is WorkBout => s.kind === "work");
  if (workBouts.length >= 2 && !structureHasSpeedContrast(segments, activityAvgVel)) {
    const work = workBouts;
    const first = work[0];
    const last = work[work.length - 1];
    const dist = segments.reduce((a, s) => a + s.distance_m, 0);
    const moving = segments.reduce((a, s) => a + s.duration_s, 0);
    const stopped = segments.reduce((a, s) => a + s.stopped_s, 0);
    const i0 = indexAtTime(streams.time ?? [], first.start_s);
    const i1 = indexAtTime(streams.time ?? [], last.end_s);
    const { avg, max } = hrOverWindow(streams.heartrate ?? [], i0, i1);
    return [{
      lap_index: 0,
      distance: Math.round(dist),
      moving_time: Math.round(moving),
      elapsed_time: Math.round(moving + stopped),
      average_speed: moving > 0 ? Math.round((dist / moving) * 100) / 100 : 0,
      average_heartrate: avg,
      max_heartrate: max,
      start_index: i0,
      end_index: i1,
      is_rest: false,
    }];
  }

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
        elapsed_time: Math.round(s.duration_s + s.stopped_s),
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
        elapsed_time: Math.round(s.duration_s + s.stopped_s),
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
    return { lap_index, vel, dur_s, valid, isFragment };
  });

  // Work-velocity boundary from the non-fragment laps — the SAME basis as
  // boutsFromLaps, so the labels agree with the detected structure.
  const normRows = rows.filter((r) => r.valid && !r.isFragment);
  const normVels = normRows.map((r) => r.vel);
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
  const adaptiveBoundary = bimodalWorkRecoveryBoundary(normVels, o.standingVelMs, {
    durations: normRows.map((r) => r.dur_s),
    minWorkSec: o.minWorkSec,
    minRecoverySec: o.minRecoverySec,
  });
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

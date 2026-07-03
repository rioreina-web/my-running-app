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
  const recoveryThreshold = o.recoveryFrac * workVel;

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
    .filter((l) => l.dist_m > 0 && l.dur_s > 0 && isFinite(l.vel));

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
  const recoveryThreshold = o.recoveryFrac * workVel;

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

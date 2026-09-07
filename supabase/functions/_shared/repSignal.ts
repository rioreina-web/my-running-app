// ============================================================================
// repSignal.ts — the rep-shape + recovery read for a quality session.
//
// WHY THIS EXISTS. Every existing metric pools a rep session into scalars —
// fitnessSignal sums the set into one EF, workoutComparison stores MEAN
// recovery drop, hrDriftPct and fadePct are session numbers. Averaging is the
// operation that destroys a slope: two sessions with identical means can be
// opposite readings (one athlete climbing 12 bpm at held pace with recovery
// closing; another flat and comfortable). The shape across the set is the
// signal. Design + calibration: REP-RECOVERY-SCORE-APPLY.md and
// CURRENT-FITNESS-APPLY.md §2.2 — every constant below was measured against
// three real sessions on 2026-08-14, not chosen from a textbook.
//
// THREE LAYERS, ALL PURE:
//   1. repWindowsFromLaps  — rep boundaries from `running_workout_laps` rows
//                            (cumulative elapsed time; work = faster than the
//                            athlete's steady pace, same isWork line the
//                            segmenter draws).
//   2. repSeriesFromStream — per-rep HR quantities from the per-second
//                            heartrate/time streams (`external_streams`).
//                            hrr60 NEEDS the stream: a rest lap's average HR
//                            includes the first ~20s still at peak, so the
//                            lap-based mean systematically understates the
//                            drop and is confounded by jog length.
//   3. scoreRepSession     — gates, sensor flags, four slopes, the final-rep
//                            close, and the verdict.
//
// THE GATES ARE THE PRODUCT (measured 2026-08-14):
//   • Reps under 90s are NOT scoreable. The 200s calibration session: 0 of 8
//     reps reached an HR plateau, hrr30 was NEGATIVE on 4 of 8 (HR still
//     rising 30s after the rep ended), true peak landed up to 20s post-rep.
//     Below the gate this module emits nothing — not a low-confidence score,
//     nothing. A different measurement wearing the same name is worse than no
//     measurement.
//   • The final rep is reported, never trended. Slopes run over reps 1..n−1;
//     the last rep is its own fact (the athlete's 10×1km closed 5s under the
//     set median after drifting — reserve, which a linear fit calls fading).
//     Symmetric: a collapsed close is also its own fact.
//   • LOW confidence withholds the verdict and keeps the facts — the Ask
//     posture (facts always render; the read is the bonus).
//
// SENSOR FLAGS, not theoretical: both fired on one real session (5×4min,
// 2026-08-06) — its fastest rep read 24 bpm BELOW a slower one, and its
// carryover ran backwards 117→91 (bodies do not recover deeper as a session
// progresses). Optical wrist HR is at its worst exactly here: rapid
// post-effort decreases are where it lags and locks onto cadence.
//
// NO PRESCRIPTION (hard rule #2). The verdict describes — "held it, at the
// edge" — and stops. It never says back off, rest, or overtrained. The
// comparative read is the athlete's to make.
//
// Pure functions, no I/O. Tests: repSignal.test.ts — the three calibration
// sessions are the fixtures and must reproduce their 2026-08-14 verdicts
// exactly.
// ============================================================================

const METERS_PER_MILE = 1609.344;

// ── Constants (CURRENT-FITNESS-APPLY.md appendix — one home) ─────────────

/** A rep must run at least this long for HR to plateau. Measured: ~200s reps
 *  settle (drift −1.4..+2.2 bpm/min); 31s reps never do (+17..+96). */
export const REP_MIN_S = 90;
/** hrPeak = mean HR over the final this-many seconds of the rep. */
export const PEAK_WINDOW_S = 15;
/** Settled = |HR drift over the final 60% of the rep| at or under this. */
export const SETTLE_MAX_BPM_PER_MIN = 3.0;
/** Slopes need at least this many points; HIGH confidence needs 6. */
export const SLOPES_MIN_REPS = 4;
export const SLOPES_HIGH_REPS = 6;
/** Direction thresholds — TOTAL change across the trended set. */
export const REC_DIR_BPM = 8; // hrr60
export const CARRY_DIR_BPM = 10; // hrAtNextRepStart
export const PACE_DIR_SEC = 2; // sec/mi (~0.02 m/s at these speeds)
export const HRCOST_DIR_BPM = 2; // hrPeak (HR feed resolution is ±1–2)
/** Final-rep close: delta vs the trended set's median pace. */
export const CLOSE_DELTA_SEC = 2;
/** HR sanity band — same as fitnessSignal. */
const HR_MIN = 90;
const HR_MAX = 205;

// ── HR source (device-aware confidence, 2026-08-15) ──────────────────────
//
// Optical wrist HR is at its worst exactly where this module reads: rapid
// post-effort decreases are where it lags and locks onto cadence — the
// 5×4min calibration session is that failure mode end to end. A chest strap's
// recovery curve is clean. The stream blob's meta carries the device name
// (vital-webhook / strava sync), so the score can carry its provenance.
//
// Policy is deliberately conservative:
//   strap   → no change.
//   optical → a HIGH score is capped at MEDIUM. The verdict still renders —
//             optical data that passed every gate and flag is good evidence,
//             it just isn't strap evidence. PROVISIONAL until a strap-vs-
//             optical comparison set exists; revisit then.
//   unknown → no change (most rows today: metadata says "Garmin", which
//             names the account, not the sensor). Infrastructure first,
//             behaviour when the data can support it.

export type HrSource = "strap" | "optical" | "unknown";

/** Best-effort classification from a device/meta name. Errs toward
 *  "unknown" — a wrong "strap" would grant unearned confidence. */
export function classifyHrSource(deviceName: string | null | undefined): HrSource {
  if (!deviceName) return "unknown";
  const d = deviceName.toLowerCase();
  if (/hrm|strap|chest|polar h(7|9|10)|wahoo tickr|garmin dual/.test(d)) return "strap";
  if (/watch|forerunner|fenix|fēnix|epix|venu|vivoactive|instinct|apple watch|coros|pace \d/.test(d)) {
    return "optical";
  }
  return "unknown";
}

// ── Layer 1 · rep windows from laps ──────────────────────────────────────

/** The lap columns this module reads — subset of what
 *  compute-workout-features already selects from `running_workout_laps`. */
export interface RepLapRow {
  lap_index?: number | null;
  is_rest?: boolean | null;
  distance_meters?: number | null;
  avg_pace_sec_per_mile?: number | null;
  moving_time_seconds?: number | null;
  elapsed_time_seconds?: number | null;
  avg_heart_rate?: number | null;
}

export interface RepWindow {
  /** 1-based rep number, in running order. */
  index: number;
  /** Offsets into the activity's elapsed-time stream, seconds. */
  startS: number;
  endS: number;
  durationS: number;
  distanceMeters: number;
  paceSecPerMile: number;
}

/** Minimum size for a lap to be a rep CANDIDATE (mirrors the segmenter's
 *  MIN_REP guards — strides are candidates here and are gated at scoring). */
const MIN_CANDIDATE_S = 20;
const MIN_CANDIDATE_M = 150;

/**
 * Rep boundaries from ordered lap rows. A lap is work when it is not flagged
 * rest AND its pace beats `workPaceCeilingSec` (the athlete's steady pace —
 * the same "faster than steady" line `segmentFromLaps` draws for `isWork`).
 * Consecutive work laps merge (auto-lap fragmentation), matching the
 * segmenter's coalesce behaviour in spirit.
 *
 * Returns [] rather than guessing when laps are absent or carry no elapsed
 * time — a session this cannot window is a session the score skips.
 */
export function repWindowsFromLaps(
  laps: readonly RepLapRow[],
  workPaceCeilingSec: number,
): RepWindow[] {
  if (!Array.isArray(laps) || laps.length === 0 || !(workPaceCeilingSec > 0)) {
    return [];
  }
  const ordered = [...laps].sort(
    (a, b) => Number(a.lap_index ?? 0) - Number(b.lap_index ?? 0),
  );
  interface Acc {
    startS: number;
    endS: number;
    meters: number;
    moving: number;
  }
  const windows: RepWindow[] = [];
  let cursor = 0; // cumulative elapsed seconds
  let open: Acc | null = null;

  const close = () => {
    if (!open) return;
    const dur = open.endS - open.startS;
    const pace = open.meters > 0 && open.moving > 0
      ? (open.moving / open.meters) * METERS_PER_MILE
      : 0;
    if (dur >= MIN_CANDIDATE_S && open.meters >= MIN_CANDIDATE_M && pace > 0) {
      windows.push({
        index: windows.length + 1,
        startS: open.startS,
        endS: open.endS,
        durationS: dur,
        distanceMeters: open.meters,
        paceSecPerMile: pace,
      });
    }
    open = null;
  };

  for (const lap of ordered) {
    const elapsed = Number(lap.elapsed_time_seconds ?? lap.moving_time_seconds ?? 0);
    const moving = Number(lap.moving_time_seconds ?? 0);
    const meters = Number(lap.distance_meters ?? 0);
    const pace = Number(lap.avg_pace_sec_per_mile ?? 0);
    const start = cursor;
    cursor += Math.max(0, elapsed);
    if (elapsed <= 0) continue;
    const isWork = !lap.is_rest && pace > 0 && pace <= workPaceCeilingSec;
    if (isWork) {
      if (open) {
        open.endS = cursor;
        open.meters += meters;
        open.moving += moving;
      } else {
        open = { startS: start, endS: cursor, meters, moving };
      }
    } else {
      close();
    }
  }
  close();
  return windows;
}

// ── Layer 2 · per-rep HR series from the per-second stream ──────────────

/** The two arrays `run-hr-trace` already selects:
 *  `external_streams->streams->heartrate` and `->time`. 1 Hz, aligned. */
export interface HrStream {
  time: readonly number[];
  hr: readonly (number | null)[];
}

export interface RepRead {
  index: number;
  durationS: number;
  paceSecPerMile: number;
  distanceMeters: number;
  /** Mean HR over the final PEAK_WINDOW_S of the rep. */
  hrPeak: number | null;
  hrMaxInRep: number | null;
  /** bpm dropped from hrPeak at +30s / +60s after the rep ends. Null when the
   *  recovery is shorter than the horizon or HR is missing. */
  hrr30: number | null;
  hrr60: number | null;
  /** Minimum HR reached before the next rep starts. */
  hrFloor: number | null;
  /** HR at the instant the next rep begins — the carryover. Null on the last rep. */
  hrAtNextRepStart: number | null;
  recoverySeconds: number | null;
  /** |HR drift| over the final 60% of the rep ≤ SETTLE_MAX_BPM_PER_MIN. */
  hrSettled: boolean;
  /** durationS < REP_MIN_S — never scoreable for hrr (measured, emphatic). */
  tooShort: boolean;
}

const validHr = (h: number | null | undefined): h is number =>
  h != null && h >= HR_MIN && h <= HR_MAX;

/** Mean valid HR over [fromS, toS) of the stream, or null. */
function hrMean(stream: HrStream, fromS: number, toS: number): number | null {
  let sum = 0, n = 0;
  for (let i = 0; i < stream.time.length; i++) {
    const t = stream.time[i];
    if (t < fromS) continue;
    if (t >= toS) break;
    const h = stream.hr[i];
    if (validHr(h)) { sum += h; n++; }
  }
  return n > 0 ? sum / n : null;
}

/** HR at time t — mean over a ±2s neighbourhood for 1 Hz noise robustness. */
function hrAt(stream: HrStream, t: number): number | null {
  return hrMean(stream, t - 2, t + 3);
}

function hrMin(stream: HrStream, fromS: number, toS: number): number | null {
  let min: number | null = null;
  for (let i = 0; i < stream.time.length; i++) {
    const t = stream.time[i];
    if (t < fromS) continue;
    if (t >= toS) break;
    const h = stream.hr[i];
    if (validHr(h) && (min == null || h < min)) min = h;
  }
  return min;
}

function hrMax(stream: HrStream, fromS: number, toS: number): number | null {
  let max: number | null = null;
  for (let i = 0; i < stream.time.length; i++) {
    const t = stream.time[i];
    if (t < fromS) continue;
    if (t >= toS) break;
    const h = stream.hr[i];
    if (validHr(h) && (max == null || h > max)) max = h;
  }
  return max;
}

/** Least-squares slope of valid HR against time over [fromS, toS), bpm/min. */
function hrDriftBpmPerMin(stream: HrStream, fromS: number, toS: number): number | null {
  const xs: number[] = [], ys: number[] = [];
  for (let i = 0; i < stream.time.length; i++) {
    const t = stream.time[i];
    if (t < fromS) continue;
    if (t >= toS) break;
    const h = stream.hr[i];
    if (validHr(h)) { xs.push(t); ys.push(h); }
  }
  if (xs.length < 10) return null;
  const n = xs.length;
  const mx = xs.reduce((s, x) => s + x, 0) / n;
  const my = ys.reduce((s, y) => s + y, 0) / n;
  let num = 0, den = 0;
  for (let i = 0; i < n; i++) { num += (xs[i] - mx) * (ys[i] - my); den += (xs[i] - mx) ** 2; }
  if (den === 0) return null;
  return (num / den) * 60;
}

/**
 * Per-rep HR quantities. `activityEndS` bounds the last rep's recovery window
 * (defaults to the stream's final sample).
 */
export function repSeriesFromStream(
  windows: readonly RepWindow[],
  stream: HrStream,
  activityEndS?: number,
): RepRead[] {
  const endOfData = activityEndS ??
    (stream.time.length > 0 ? stream.time[stream.time.length - 1] : 0);
  return windows.map((w, i) => {
    const next = windows[i + 1] ?? null;
    const recEnd = next ? next.startS : Math.min(w.endS + 120, endOfData);
    const recoverySeconds = next
      ? Math.max(0, next.startS - w.endS)
      : (endOfData > w.endS ? Math.min(120, endOfData - w.endS) : null);

    const hrPeak = hrMean(stream, w.endS - PEAK_WINDOW_S, w.endS);
    const drift = hrDriftBpmPerMin(stream, w.endS - w.durationS * 0.6, w.endS);
    const tooShort = w.durationS < REP_MIN_S;
    // A rep the drift can't be read on is NOT settled — unknown ≠ fine.
    const hrSettled = !tooShort && drift != null &&
      Math.abs(drift) <= SETTLE_MAX_BPM_PER_MIN;

    const horizon = (h: number): number | null => {
      if (hrPeak == null) return null;
      if (recoverySeconds == null || recoverySeconds < h) return null;
      const at = hrAt(stream, w.endS + h);
      return at != null ? hrPeak - at : null;
    };

    return {
      index: w.index,
      durationS: w.durationS,
      paceSecPerMile: w.paceSecPerMile,
      distanceMeters: w.distanceMeters,
      hrPeak,
      hrMaxInRep: hrMax(stream, w.startS, w.endS),
      hrr30: horizon(30),
      hrr60: horizon(60),
      hrFloor: hrMin(stream, w.endS, recEnd),
      hrAtNextRepStart: next ? hrAt(stream, next.startS) : null,
      recoverySeconds,
      hrSettled,
      tooShort,
    };
  });
}

// ── Layer 3 · the session score ──────────────────────────────────────────

export type Direction3 = "up" | "down" | "flat";

export interface SlopeRead {
  /** Total change across the trended set (slope × (points − 1)). */
  total: number;
  points: number;
  direction: Direction3;
}

export type VerdictKey =
  | "inside_capacity"
  | "at_the_edge"
  | "faded_unclear"
  | "over_the_edge";

export const VERDICT_LABEL: Record<VerdictKey, string> = {
  inside_capacity: "comfortably inside capacity",
  at_the_edge: "held it — at the edge",
  faded_unclear: "faded without cost rising",
  over_the_edge: "over the edge",
};

export type RepConfidence = "high" | "medium" | "low";

export interface FinalRepRead {
  paceSecPerMile: number;
  /** vs the trended set's median pace. Negative = closed faster. */
  deltaVsMedianSec: number;
  close: "fast" | "faded" | "even";
}

export interface RepSessionScore {
  scored: boolean;
  /** Where the HR came from — carried so surfaces can explain a withheld or
   *  capped read ("wrist HR lags on recovery"). */
  hrSource: HrSource;
  /** Why not, when !scored — plain prose, honest. */
  reason: string | null;
  repsTotal: number;
  repsUsable: number;
  /** First usable rep's hrr60 — freshest reading, cross-session comparable. */
  level: number | null;
  /** The four slopes, over reps 1..n−1 of the usable set. */
  recovery: SlopeRead | null; // hrr60; down = closing
  carryover: SlopeRead | null; // hrAtNextRepStart; up = accumulating
  pace: SlopeRead | null; // sec/mi; up = fading
  hrCost: SlopeRead | null; // hrPeak at held pace; up = rising
  finalRep: FinalRepRead | null;
  /** Machine keys; each also drops confidence to LOW. */
  flags: string[];
  confidence: RepConfidence;
  /** Null when unscored OR withheld at LOW — facts still render. */
  verdict: { key: VerdictKey; label: string } | null;
}

function lsqTotal(values: readonly (number | null)[]): SlopeRead | null {
  const pts: Array<[number, number]> = [];
  values.forEach((v, i) => { if (v != null && isFinite(v)) pts.push([i, v]); });
  if (pts.length < 3) return null;
  const n = pts.length;
  const mx = pts.reduce((s, p) => s + p[0], 0) / n;
  const my = pts.reduce((s, p) => s + p[1], 0) / n;
  let num = 0, den = 0;
  for (const [x, y] of pts) { num += (x - mx) * (y - my); den += (x - mx) ** 2; }
  if (den === 0) return null;
  const slope = num / den;
  return { total: round1(slope * (n - 1)), points: n, direction: "flat" };
}

function withDirection(read: SlopeRead | null, threshold: number): SlopeRead | null {
  if (!read) return null;
  return {
    ...read,
    direction: read.total >= threshold ? "up" : read.total <= -threshold ? "down" : "flat",
  };
}

const round1 = (x: number): number => Math.round(x * 10) / 10;

const median = (xs: readonly number[]): number => {
  const s = [...xs].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};

/**
 * Score one session's rep series. Deterministic; safe on any input — a
 * session that fails a gate returns `{scored:false, reason}` and nothing else.
 */
export function scoreRepSession(
  reps: readonly RepRead[],
  opts?: { hrSource?: HrSource },
): RepSessionScore {
  const hrSource: HrSource = opts?.hrSource ?? "unknown";
  const base: RepSessionScore = {
    scored: false, reason: null, hrSource,
    repsTotal: reps.length, repsUsable: 0,
    level: null, recovery: null, carryover: null, pace: null, hrCost: null,
    finalRep: null, flags: [], confidence: "low", verdict: null,
  };
  if (reps.length === 0) return { ...base, reason: "no reps detected" };

  const usable = reps.filter((r) => !r.tooShort && r.hrSettled);
  base.repsUsable = usable.length;

  if (usable.length < SLOPES_MIN_REPS) {
    const short = reps.filter((r) => r.tooShort).length;
    const reason = short > reps.length / 2
      ? `${short}/${reps.length} reps under ${REP_MIN_S}s — HR never plateaus on short reps, recovery is unreadable`
      : `only ${usable.length} usable reps (need ${SLOPES_MIN_REPS})`;
    return { ...base, reason };
  }

  // The final rep of the SESSION is reported, never trended (decided
  // 2026-08-15). Slopes over the usable set minus that rep.
  const lastIndex = reps[reps.length - 1].index;
  const trended = usable.filter((r) => r.index !== lastIndex);
  const finalUsable = usable.find((r) => r.index === lastIndex) ?? null;

  const recovery = withDirection(lsqTotal(trended.map((r) => r.hrr60)), REC_DIR_BPM);
  const carryover = withDirection(lsqTotal(trended.map((r) => r.hrAtNextRepStart)), CARRY_DIR_BPM);
  const pace = withDirection(lsqTotal(trended.map((r) => r.paceSecPerMile)), PACE_DIR_SEC);
  const hrCost = withDirection(lsqTotal(trended.map((r) => r.hrPeak)), HRCOST_DIR_BPM);

  const level = usable.map((r) => r.hrr60).find((v) => v != null) ?? null;

  let finalRep: FinalRepRead | null = null;
  if (finalUsable && trended.length >= 2) {
    const med = median(trended.map((r) => r.paceSecPerMile));
    const delta = round1(finalUsable.paceSecPerMile - med);
    finalRep = {
      paceSecPerMile: round1(finalUsable.paceSecPerMile),
      deltaVsMedianSec: delta,
      close: delta <= -CLOSE_DELTA_SEC ? "fast" : delta >= CLOSE_DELTA_SEC ? "faded" : "even",
    };
  }

  // ── Sensor flags — each is physiologically backwards, each → LOW ──
  const flags: string[] = [];
  if (carryover && carryover.total <= -CARRY_DIR_BPM) {
    // Recovering DEEPER as the session progresses. Bodies don't; sensors do.
    flags.push("carryover_backwards");
  }
  if (
    pace && hrCost &&
    pace.total <= -PACE_DIR_SEC && hrCost.total <= -HRCOST_DIR_BPM
  ) {
    // Faster reps reading cheaper — pace and HR anti-correlated.
    flags.push("pace_hr_anticorrelated");
  }

  const hrr60Count = trended.filter((r) => r.hrr60 != null).length;
  let confidence: RepConfidence =
    hrr60Count >= SLOPES_HIGH_REPS ? "high"
    : hrr60Count >= SLOPES_MIN_REPS ? "medium"
    : "low";
  if (flags.length > 0) confidence = "low";
  // Optical wrist HR: a clean session is capped at MEDIUM, never HIGH — the
  // sensor's recovery lag is exactly what hrr60 measures. Strap and unknown
  // are untouched. (Provisional policy; see the HrSource header.)
  if (hrSource === "optical" && confidence === "high") confidence = "medium";

  // ── Verdict — the combination, withheld at LOW (facts still render) ──
  let verdict: RepSessionScore["verdict"] = null;
  if (confidence !== "low") {
    const held = pace == null || pace.direction !== "up";
    const costRising = hrCost?.direction === "up";
    const recClosing = recovery?.direction === "down";
    let key: VerdictKey;
    if (held && !costRising && !recClosing) key = "inside_capacity";
    else if (held) key = "at_the_edge";
    else if (!costRising && !recClosing) key = "faded_unclear";
    else key = "over_the_edge";
    verdict = { key, label: VERDICT_LABEL[key] };
  }

  return {
    ...base,
    scored: true,
    level: level != null ? round1(level) : null,
    recovery, carryover, pace, hrCost,
    finalRep, flags, confidence, verdict,
  };
}

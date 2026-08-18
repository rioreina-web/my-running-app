// ============================================================================
// fitnessCurve.ts — damping for the fitness estimate.
//
// WHY THIS EXISTS. `generateFitnessPrediction` re-derives the estimate from
// near-scratch every night, off a rolling 14-day window of quality work. That
// window turns over as sessions age in and out, so the raw estimate moves for
// reasons that have nothing to do with the athlete. Observed on the
// calibration athlete, two runs on the SAME DAY:
//
//     2026-08-15 03:30   32:00
//     2026-08-15 15:03   33:44      ← 104 s apart, same body
//
// What has been hiding this is not smoothing — it is the ±2% validation band
// and the ±5% race clamp, which pin the number flat until the pin moves and
// then it jumps. Flat, flat, flat, jump is the wrong shape twice over.
//
// THE MODEL. Fitness is an ACCUMULATION. One session is evidence, not a
// measurement: some days are tired, some are worn down, some are the best
// you've felt in a month. A single workout should nudge the curve; a month of
// them should move it. So the state moves a fraction of the way toward each
// new observation rather than jumping to it:
//
//     smoothed = prior + (raw − prior) · α,     α = 1 − exp(−Δt / τ)
//
// Exponential, so old evidence fades on its own. That is the crucial
// difference from the "snapshots feed snapshots" ratchet the anti-ratchet
// comment in fitnessPrediction.ts warns about: THAT compounds the OUTPUT, so a
// transient fast reading persists for months. THIS accumulates EVIDENCE with
// decay, so a flattering day is outvoted by the fortnight around it and then
// forgotten.
//
// Irregular sampling is handled honestly. Δt is real elapsed days, so a gap
// (missed cron, app closed for a week) lets the curve travel further rather
// than pretending the last sample was yesterday.
//
// WHAT IS ALLOWED TO MOVE IT HARD. A declared race or time trial. That is a
// measurement, not evidence, and it resets the level outright — the same
// principle the anchor already runs on: races are declared, never inferred.
//
// Pure functions, no I/O. Tests: fitnessCurve.test.ts.
// ============================================================================

/** Days for the curve to close ~63% of a gap. Three weeks: a strong week
 *  nudges, a strong month moves it. Deliberately slower than a training block
 *  is long, so the curve describes the block rather than chasing it. */
export const DEFAULT_TAU_DAYS = 21;

/** Hard ceiling on one day's movement, as a fraction of pace. 0.5% of a ~5:10
 *  10K pace is ~1.5 s/mi ≈ 10 s over 10K. Enough for a genuine block to move
 *  the curve in a fortnight; not enough for any single session to jolt it,
 *  whatever the evidence claims. Belt and braces with α — α alone already
 *  limits movement, but a huge raw swing (window turnover, a mis-parsed
 *  session) can still clear it. */
export const MAX_DAILY_MOVE_PCT = 0.005;

/** Beyond this gap, treat the prior as too stale to damp against — the athlete
 *  has been away and the curve should re-seat on current evidence rather than
 *  crawl back from a months-old level. */
export const STALE_PRIOR_DAYS = 45;

export interface CurveInput {
  /** Tonight's raw estimate (sec/mile at 10K pace). */
  rawPace: number;
  /** The last SMOOTHED value, or null on first run / after a long gap. */
  priorPace: number | null;
  /** Real elapsed days since `priorPace` was recorded. */
  deltaDays: number;
  /** A race or time trial was declared in this window — reset, don't damp. */
  hardReset?: boolean;
  tauDays?: number;
  maxDailyMovePct?: number;
}

export interface CurveResult {
  /** What to store and serve. */
  pace: number;
  /** Fraction of the gap actually travelled (0 = held, 1 = jumped to raw). */
  alpha: number;
  /** True when MAX_DAILY_MOVE_PCT bound the step rather than α. */
  capped: boolean;
  /** Why the curve behaved as it did — for the honest-coverage note. */
  reason: "first-sample" | "stale-prior" | "hard-reset" | "damped";
}

/**
 * Move the fitness curve toward tonight's raw estimate.
 *
 * Returns `rawPace` unchanged on the first sample, after a stale gap, or on a
 * declared race — those are the three cases where damping would be lying about
 * what we know. Otherwise the step is `α` of the gap, then clamped to
 * `maxDailyMovePct` of the prior.
 */
export function smoothFitnessPace(input: CurveInput): CurveResult {
  const {
    rawPace,
    priorPace,
    deltaDays,
    hardReset = false,
    tauDays = DEFAULT_TAU_DAYS,
    maxDailyMovePct = MAX_DAILY_MOVE_PCT,
  } = input;

  if (!(rawPace > 0) || !isFinite(rawPace)) {
    return { pace: rawPace, alpha: 1, capped: false, reason: "first-sample" };
  }
  if (hardReset) {
    return { pace: rawPace, alpha: 1, capped: false, reason: "hard-reset" };
  }
  if (priorPace == null || !(priorPace > 0) || !isFinite(priorPace)) {
    return { pace: rawPace, alpha: 1, capped: false, reason: "first-sample" };
  }
  if (!(deltaDays >= 0) || !isFinite(deltaDays) || deltaDays > STALE_PRIOR_DAYS) {
    return { pace: rawPace, alpha: 1, capped: false, reason: "stale-prior" };
  }

  // Two samples the same day (a manual run alongside the cron) must not each
  // take a full day's step — that is how 32:00 and 33:44 landed hours apart.
  // A zero gap moves nothing; the curve advances on elapsed time, not on how
  // often we happened to recompute.
  const alpha = 1 - Math.exp(-Math.max(deltaDays, 0) / Math.max(tauDays, 0.5));

  let next = priorPace + (rawPace - priorPace) * alpha;

  // Cap scales with the gap too, so a legitimate week-long absence can still
  // travel a week's worth rather than one day's.
  const maxMove = priorPace * maxDailyMovePct * Math.max(deltaDays, 1);
  const move = next - priorPace;
  let capped = false;
  if (Math.abs(move) > maxMove) {
    next = priorPace + Math.sign(move) * maxMove;
    capped = true;
  }

  return { pace: next, alpha, capped, reason: "damped" };
}

/**
 * Marker this model appends to every `data_source` it writes. A row without it
 * was produced by some other program against some other model.
 *
 * Kept in lockstep with fitnessPrediction.ts's `dataSource = \`${x} · v2\``.
 */
export const SERVER_SOURCE_MARKER = "· v2";

/** True when this snapshot row was written by THIS model. */
export function isOwnSnapshot(dataSource: string | null | undefined): boolean {
  return typeof dataSource === "string" && dataSource.includes(SERVER_SOURCE_MARKER);
}

/** UTC calendar day as YYYY-MM-DD — the grain `fitness_snapshots` upserts on. */
function utcDay(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

/**
 * Pick the most recent prior smoothed value from snapshot history.
 *
 * Deliberately MOST RECENT, never fastest. "Fastest in N weeks" is the
 * ratchet — it lets one flattering reading set a floor that outlives the
 * fitness that produced it. The curve's own decay is what protects against
 * noise; the selection rule must not add a second, one-directional memory.
 *
 * FOREIGN ROWS ARE SKIPPED (2026-08-17). `fitness_snapshots` had two writers:
 * this model, and the iOS on-device predictor, which sees no laps, no weather
 * and no curve. Damping is only sound against your OWN previous output —
 * smoothing toward another model's answer doesn't average two opinions, it
 * inherits one and then slowly leaves it. Two device rows (both 33:44 against
 * this model's 32:00) pulled the athlete ~100 s off and would have taken six
 * weeks to unwind at τ=21d.
 *
 * The device writer is now disabled, so this guard is belt-and-braces — which
 * is the point: the curve must not be re-poisonable by the next thing that
 * writes to this table. A row with no `dataSource` at all is treated as
 * foreign; unknown provenance is not own provenance.
 */
export function mostRecentPrior<
  T extends { createdAt: string; estimated10kPaceSeconds: number; dataSource?: string | null },
>(
  snapshots: readonly T[],
  before: Date,
): { pace: number; deltaDays: number } | null {
  let best: T | null = null;
  let bestMs = -Infinity;
  const beforeMs = before.getTime();

  // SKIP TODAY'S OWN ROW (2026-08-17). `fitness_snapshots` holds at most one
  // row per UTC day and the writer UPDATES it in place, so a row sharing
  // `before`'s UTC day is the row this run is about to overwrite. Damping
  // toward it is damping toward yourself: a rerun two hours after the last
  // one gets deltaDays 0.086 -> alpha 0.004, and moves 0.4% of the gap.
  //
  // That made every same-day rerun a near no-op, which is the worst possible
  // property while calibrating — deploy a model change, re-run, see the old
  // number, conclude the change did nothing. It is also what hid the
  // 2:37 -> 2:29 correction until the marker was stripped by hand.
  //
  // Excluding the day being written makes the prior YESTERDAY's answer, which
  // is what "move a fraction of the way toward tonight's estimate" always
  // meant. The nightly cron is unaffected: it is the first write of its day,
  // so there is no same-day row to skip.
  const beforeDay = utcDay(before.getTime());

  for (const s of snapshots) {
    const ms = new Date(s.createdAt).getTime();
    if (!isFinite(ms) || ms > beforeMs) continue;
    if (!(s.estimated10kPaceSeconds > 0)) continue;
    if (!isOwnSnapshot(s.dataSource)) continue;
    if (utcDay(ms) === beforeDay) continue;
    if (ms > bestMs) { bestMs = ms; best = s; }
  }
  if (best == null) return null;
  return {
    pace: best.estimated10kPaceSeconds,
    deltaDays: (beforeMs - bestMs) / 86_400_000,
  };
}

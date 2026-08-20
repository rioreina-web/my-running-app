/**
 * recoveryRead.ts — "Is the same pace costing more beats than usual?"
 *
 * THE QUESTION THIS ANSWERS
 * ------------------------
 * A runner finishes a hard session. The next day they go out easy. If they are
 * still carrying the session, their heart works harder to hold the same pace —
 * they are away from homeostasis and it shows up as beats, not as pace. This
 * module reads that: it compares the CARDIAC COST of a session against what
 * that athlete's own history says the same pace normally costs, and reports the
 * gap with an honest error bar.
 *
 * It runs on EVERY session, not just easy runs. The baseline is per PACE BAND,
 * so a threshold rep is compared to threshold reps and a shakeout to shakeouts.
 *
 * COST = beats per mile = avgHr × paceMinutesPerMile
 * Intuitive ("this mile cost me 1,070 beats"), and it is the quantity that
 * turned out to be tight in real data: within a pace band, one athlete's
 * cardiac cost has a coefficient of variation of 1.2–3.8%. A 3% excursion is
 * therefore visible. That tightness is the entire reason this can work.
 *
 * WHAT THE DATA SAID — AND WHAT IT DID NOT (2026-08-19, n=145 runs, 4 months)
 * --------------------------------------------------------------------------
 * The honest finding, recorded here so nobody re-discovers it the hard way:
 *
 *   • On the athlete tested, the DAY-AFTER effect was NOT DETECTABLE. Day 1
 *     after a hard session read +0.16 bpm vs fully-recovered, 95% CI
 *     [-1.66, +1.99]. Day 2 +0.02, day 3 -0.21. Flat.
 *   • The confounders are LARGER THAN THE SIGNAL. Time of day was worth
 *     5.4 bpm (morning runs read that much lower at identical pace and
 *     conditions). Pace was worth 1.9 bpm per 10 sec/mile. Duration 0.5 bpm
 *     per 10 min. A version of this metric that ignores those would have
 *     reported time-of-day as fatigue — and before time-of-day was added to
 *     the model, the dew-point coefficient came out NEGATIVE, i.e. the model
 *     claimed humidity lowers heart rate. That is what an unmodelled
 *     confounder looks like from the inside.
 *   • Cooldown jogs starting ~1h after a workout DID read +3.3 bpm
 *     (p=0.004, d=0.95) — but that is the same session still ending, not
 *     recovery. `MIN_HOURS_AFTER_HARD` exists to keep that out.
 *
 * So this module is built to STAY QUIET. It reports "no read" freely and only
 * speaks when the excursion clears the athlete's own noise floor by a margin.
 * That is deliberate: on the evidence available, a metric that always has an
 * opinion here would be manufacturing one. Consistent with the house rule
 * already set in `docs/specs/recovery-trend-v2-2026-07-27.md` — detection, not
 * diagnosis; range and confidence, never false precision.
 *
 * SELF-CALIBRATING, NOT CALIBRATED BY US
 * --------------------------------------
 * Every threshold is in units of the ATHLETE'S OWN dispersion (MAD-derived
 * sigma), never in absolute bpm. A metronomic athlete gets tight bands; a
 * variable one gets wide bands, automatically, from the same code. Nothing
 * here is tuned to the one athlete it was developed against — which matters,
 * because that athlete is unusually consistent (easy-pace IQR 7:17–7:41) and
 * is the WORST case for detecting this effect, not the typical one.
 *
 * Pure functions, no I/O. See recoveryRead.test.ts.
 */

// ── Tunables (exported so tests and tuning have one home) ────────────────────

/** Trailing window the baseline is drawn from. */
export const WINDOW_DAYS = 42;
/** Minimum in-band, same-daypart samples before we will say anything at all. */
export const MIN_SAMPLES = 8;
/** Above this many samples the read is called high-confidence. */
export const STRONG_SAMPLES = 15;
/** |z| below this is NOISE. We say "nothing detected", not "recovered well". */
export const Z_QUIET = 1.5;
/** |z| at or above this is a real excursion worth surfacing. */
export const Z_ELEVATED = 1.5;
/** |z| at or above this is a large excursion. */
export const Z_VERY_ELEVATED = 2.5;
/**
 * Sigma floor, as a fraction of the baseline cost. A freak-tight window must
 * not make ordinary variation look significant: 1.2% is the tightest CV seen
 * in real data, so we refuse to believe any athlete is tighter than that.
 */
export const SIGMA_FLOOR_PCT = 0.012;
/**
 * Sessions closer than this to the end of a hard effort are the SAME session
 * still finishing (cooldown jogs, second legs of a double), not a recovery
 * datapoint. Measured: those read +3.3 bpm and would masquerade as fatigue.
 */
export const MIN_HOURS_AFTER_HARD = 6;
/**
 * Anything slower than this ratio to easy pace gets no read. In real data the
 * slower-than-easy bucket had CV 30% and sigma 403 beats/mile — it mixes true
 * recovery jogs with walk breaks, hikes and stopped GPS. There is no baseline
 * to be had there, so we do not pretend there is.
 */
export const MAX_RATIO_FOR_READ = 1.06;
/** Sessions shorter than this never produce a read — HR has not settled. */
export const MIN_MINUTES = 12;
/**
 * Heart-rate cost of climbing, in bpm per metre of gain per mile.
 *
 * Measured on 100 easy runs: **+3.16 bpm per 10 m/mile of climb**
 * (R² 0.699 → 0.710; hilly tercile vs flat +1.90 bpm, p=0.064, d=0.46,
 * monotone across terciles −1.18 → +0.51 → +0.71).
 *
 * This is the ONLY covariate beyond pace, duration and daypart that improved
 * the model — and at ~1.9 bpm between a flat and a hilly easy run it is an
 * order of magnitude larger than the day-after fatigue effect this module is
 * looking for (+0.16 bpm). Uncorrected, a hilly recovery run reads as
 * fatigue. Correcting for it is not optional.
 *
 * Caveats, so nobody treats this as settled: n=1 athlete, p=0.064, and the
 * range sampled is 0–22 m/mile — rolling Austin terrain, not mountains. The
 * relationship is assumed linear because there is no data to justify a curve.
 * Distinct from `effortModel.gradeFactor`, which adjusts PACE from per-lap
 * grade; this adjusts HEART RATE from whole-session gain. Different axes.
 */
export const CLIMB_BPM_PER_M_PER_MILE = 0.316;
/**
 * How far this session's heat index may sit from the baseline's before the
 * read is refused, in °F. Floor value; the real gate is the wider of this and
 * `HEAT_OUT_OF_RANGE_SIGMA` × the baseline's own spread, so an athlete who
 * genuinely trains across varied conditions is not blocked constantly.
 *
 * WHY A GUARD AND NOT A CORRECTION. Heat plainly changes heart rate — but this
 * module never compares a hot run to a cold one. It compares a session to
 * same-daypart sessions from the last six weeks, and the measured spread of
 * heat index INSIDE such a window is only ~6 °F. Even at the most generous
 * coefficient that could be fitted (+0.11 bpm/°F), 6 °F is worth ~0.7 bpm —
 * a fifth of the 3.9 bpm noise floor and an eighth of what it takes to trigger
 * a flag. Holding conditions roughly constant by MATCHING is doing the work
 * that a correction term would do, without a coefficient to get wrong.
 *
 * Held against that: with the season held constant (within-month, demeaned),
 * the heat effect measured +0.014 bpm/°F, r=+0.03, p=0.76 — nothing. The
 * apparent evening heat effect (+0.11 bpm/°F, R² 0.491 → 0.521) is confounded
 * with the calendar: hot evenings are late-summer evenings, and adding a
 * season trend collapses the coefficient to +0.02.
 *
 * So the risk is not ordinary weather. It is TRAVEL, a RACE somewhere else, or
 * a genuine heat wave — where the baseline was built in conditions the session
 * does not share and the matching assumption silently fails. There the honest
 * answer is no answer. 12 °F ≈ 2× the observed within-window spread; past that
 * we would be extrapolating a coefficient we do not trust.
 */
export const HEAT_OUT_OF_RANGE_F = 12;
export const HEAT_OUT_OF_RANGE_SIGMA = 2;

/**
 * Pace bands, as a RATIO of session pace to the athlete's easy-pace anchor.
 * Expressed as a ratio rather than absolute pace so the bands travel with the
 * athlete's fitness: when easy pace drops, every band moves with it and last
 * month's baseline stays comparable.
 */
export const BANDS: ReadonlyArray<{ id: string; label: string; maxRatio: number }> = [
  { id: "vo2", label: "10K pace and faster", maxRatio: 0.72 },
  { id: "threshold", label: "Threshold", maxRatio: 0.80 },
  { id: "marathon", label: "Marathon pace", maxRatio: 0.88 },
  { id: "steady", label: "Steady", maxRatio: 0.94 },
  { id: "moderate", label: "Moderate", maxRatio: 1.00 },
  { id: "easy", label: "Easy", maxRatio: MAX_RATIO_FOR_READ },
];

// ── Inputs & outputs ────────────────────────────────────────────────────────

export interface CostSample {
  /** Session start, ISO 8601. */
  startedAt: string;
  paceSecPerMile: number;
  avgHr: number;
  minutes: number;
  /** Hours since the last hard session ended. Null when there is no prior hard
   *  session — that is a valid baseline sample, not a missing one. */
  hoursSinceHard?: number | null;
  /** Elevation gain in metres per mile. Null/absent means uncorrected — the
   *  read still happens, at reduced confidence, rather than being refused. */
  elevationGainMetersPerMile?: number | null;
  /** Apparent temperature in °F. Use `heatIndexF(tempF, dewPointF)` to derive
   *  it from the two columns `weather_actual` already carries. Null/absent
   *  simply skips the out-of-range guard. */
  heatIndexF?: number | null;
  tempF?: number | null;
  dewPointF?: number | null;
}

export type Verdict =
  | "no-read"
  | "nothing-detected"
  | "elevated"
  | "very-elevated"
  | "lower-than-usual";

export interface RecoveryRead {
  /** Beats per mile for this session. Always present when inputs are sane. */
  cost: number | null;
  bandId: string | null;
  bandLabel: string | null;
  /** Median in-band cost over the window, same daypart. */
  baseline: number | null;
  /** The athlete's own dispersion, MAD-derived, floored. */
  sigma: number | null;
  /** (cost − baseline) / sigma. */
  z: number | null;
  deltaPct: number | null;
  verdict: Verdict;
  /** Why there is no read, in plain words. Null when there is a read. */
  blockedBy: string | null;
  samplesUsed: number;
  confidence: "high" | "moderate" | "low";
}

// ── Small helpers ───────────────────────────────────────────────────────────

const round1 = (x: number): number => Math.round(x * 10) / 10;
const round2 = (x: number): number => Math.round(x * 100) / 100;

/** Beats per mile. The whole metric rests on this one line. */
export function cardiacCost(paceSecPerMile: number, avgHr: number): number | null {
  if (!isFinite(paceSecPerMile) || paceSecPerMile <= 0) return null;
  if (!isFinite(avgHr) || avgHr <= 0) return null;
  return (paceSecPerMile / 60) * avgHr;
}

/**
 * Cardiac cost with the climb paid back — what this session would have cost on
 * the flat. The correction is applied to HEART RATE before the cost is formed,
 * so it stays in the units the coefficient was measured in.
 *
 * Missing elevation returns the uncorrected cost rather than refusing: a run
 * with no elevation data is still worth reading, it is just read with less
 * confidence (see `confidence` on the result).
 */
export function flatEquivalentCost(s: CostSample): number | null {
  const raw = cardiacCost(s.paceSecPerMile, s.avgHr);
  if (raw == null) return null;
  const climb = s.elevationGainMetersPerMile;
  if (climb == null || !isFinite(climb) || climb <= 0) return raw;
  const hrFlat = s.avgHr - CLIMB_BPM_PER_M_PER_MILE * climb;
  // Never let the correction invert the sign of the measurement.
  if (!(hrFlat > 0)) return raw;
  return (s.paceSecPerMile / 60) * hrFlat;
}

/**
 * Relative humidity from temperature and dew point (Magnus formula), then the
 * NOAA Rothfusz heat index. Below 80 °F Rothfusz is not valid, so the simple
 * Steadman form is used instead — same convention NOAA publishes.
 *
 * This exists so callers can derive one number from the `temp_f` / `dew_point_f`
 * pair that `training_logs.weather_actual` already stores, rather than every
 * caller inventing its own combination.
 */
export function heatIndexF(tempF: number, dewPointF: number): number | null {
  if (!isFinite(tempF) || !isFinite(dewPointF)) return null;
  const c = (f: number) => ((f - 32) * 5) / 9;
  const a = 17.625, b = 243.04;
  const t = c(tempF), td = c(dewPointF);
  const R = 100 * (Math.exp((a * td) / (b + td)) / Math.exp((a * t) / (b + t)));
  const rh = Math.max(0, Math.min(100, R));
  if (tempF < 80) return 0.5 * (tempF + 61 + (tempF - 68) * 1.2 + rh * 0.094);
  const T = tempF;
  return -42.379 + 2.04901523 * T + 10.14333127 * rh - 0.22475541 * T * rh
    - 6.83783e-3 * T * T - 5.481717e-2 * rh * rh + 1.22874e-3 * T * T * rh
    + 8.5282e-4 * T * rh * rh - 1.99e-6 * T * T * rh * rh;
}

/** The session's heat index, derived if not supplied. */
export function sampleHeatIndex(s: CostSample): number | null {
  if (s.heatIndexF != null && isFinite(s.heatIndexF)) return s.heatIndexF;
  if (s.tempF != null && s.dewPointF != null) return heatIndexF(s.tempF, s.dewPointF);
  return null;
}

export function median(xs: number[]): number {
  if (xs.length === 0) return NaN;
  const s = [...xs].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}

/**
 * Median absolute deviation, scaled to a normal-equivalent sigma. Robust:
 * one blown-up session in the window must not widen the band so far that the
 * next three real excursions go unnoticed.
 */
export function madSigma(xs: number[]): number {
  if (xs.length < 2) return NaN;
  const m = median(xs);
  return 1.4826 * median(xs.map((x) => Math.abs(x - m)));
}

/** Which band a pace falls in. Null for anything slower than the easy band. */
export function bandFor(paceSecPerMile: number, easyPaceSecPerMile: number): { id: string; label: string } | null {
  if (!(paceSecPerMile > 0) || !(easyPaceSecPerMile > 0)) return null;
  const ratio = paceSecPerMile / easyPaceSecPerMile;
  for (const b of BANDS) if (ratio < b.maxRatio) return { id: b.id, label: b.label };
  return null;
}

/**
 * Time of day is MATCHED, not corrected. Measured at 5.4 bpm on real data —
 * the single largest confounder, larger than any fatigue effect we could
 * find. Matching cannot get the sign wrong; a regression on thin data can.
 *
 * (2026-08-19) morning/evening split → circular hour proximity. The original
 * split classified by `getHours() < 11` — the RUNTIME'S local clock. On the
 * athlete's phone that is their morning; on a UTC edge function a 6 a.m.
 * Austin run (11:05Z) lands on the wrong side of the line and every baseline
 * silently mixes dayparts. Matching each session to history within ±3 clock
 * hours (circular, UTC) needs no timezone knowledge at all: a 12Z run matches
 * other 12Z runs whether that means Austin dawn or Berlin lunch.
 */
export const DAYPART_MATCH_HOURS = 3;

/** Fractional hour-of-day in UTC — deterministic in any runtime. */
export function startHourUtc(iso: string): number {
  const d = new Date(iso);
  return d.getUTCHours() + d.getUTCMinutes() / 60;
}

/** Circular distance between two hours-of-day (23:30 and 00:30 are 1 apart). */
export function hourDistance(a: number, b: number): number {
  const d = Math.abs(a - b) % 24;
  return Math.min(d, 24 - d);
}

/** @deprecated kept only for callers that still want a coarse label; the
 *  matching itself no longer uses it. Uses UTC, so the label is arbitrary. */
export function isMorning(iso: string): boolean {
  return startHourUtc(iso) < 11;
}

const daysBetween = (a: string, b: string): number =>
  Math.abs(new Date(a).getTime() - new Date(b).getTime()) / 86_400_000;

/** A sample is eligible to sit in a baseline. Deliberately stricter than the
 *  bar for GETTING a read: the baseline is the thing everything else is
 *  measured against, so it may only contain clean, comparable sessions. */
export function eligibleForBaseline(s: CostSample, easyPace: number): boolean {
  if (!(s.minutes >= MIN_MINUTES)) return false;
  if (bandFor(s.paceSecPerMile, easyPace) == null) return false;
  if (flatEquivalentCost(s) == null) return false;
  if (s.hoursSinceHard != null && s.hoursSinceHard < MIN_HOURS_AFTER_HARD) return false;
  return true;
}

// ── The read ────────────────────────────────────────────────────────────────

/**
 * Read one session against the athlete's own history.
 *
 * `history` may contain the session itself; it is excluded by identity of
 * `startedAt` so callers do not have to pre-filter. Only samples STRICTLY
 * BEFORE the session are used — a baseline must never see the future, or the
 * number silently changes when the page is reloaded next week.
 */
export function readSession(
  session: CostSample,
  history: CostSample[],
  easyPaceSecPerMile: number,
): RecoveryRead {
  const empty = (blockedBy: string, cost: number | null = null): RecoveryRead => ({
    cost,
    bandId: null,
    bandLabel: null,
    baseline: null,
    sigma: null,
    z: null,
    deltaPct: null,
    verdict: "no-read",
    blockedBy,
    samplesUsed: 0,
    confidence: "low",
  });

  const cost = flatEquivalentCost(session);
  if (cost == null) return empty("no heart rate on this session");
  if (!(easyPaceSecPerMile > 0)) return empty("no easy-pace anchor for this athlete", round1(cost));
  if (!(session.minutes >= MIN_MINUTES)) {
    return empty(`under ${MIN_MINUTES} minutes — heart rate has not settled`, round1(cost));
  }

  const band = bandFor(session.paceSecPerMile, easyPaceSecPerMile);
  if (band == null) return empty("slower than easy pace — no reliable baseline exists there", round1(cost));

  if (session.hoursSinceHard != null && session.hoursSinceHard < MIN_HOURS_AFTER_HARD) {
    return empty("within hours of a hard session — this is the same effort still ending", round1(cost));
  }

  const sessionHour = startHourUtc(session.startedAt);
  const pool = history.filter((h) =>
    h.startedAt !== session.startedAt &&
    new Date(h.startedAt).getTime() < new Date(session.startedAt).getTime() &&
    daysBetween(h.startedAt, session.startedAt) <= WINDOW_DAYS &&
    hourDistance(startHourUtc(h.startedAt), sessionHour) <= DAYPART_MATCH_HOURS &&
    eligibleForBaseline(h, easyPaceSecPerMile) &&
    bandFor(h.paceSecPerMile, easyPaceSecPerMile)?.id === band.id
  );

  const costs = pool
    .map((h) => flatEquivalentCost(h))
    .filter((c): c is number => c != null);

  if (costs.length < MIN_SAMPLES) {
    return {
      ...empty(
        `only ${costs.length} comparable session${costs.length === 1 ? "" : "s"} at this pace and time of day in the last ${WINDOW_DAYS} days — needs ${MIN_SAMPLES}`,
        round1(cost),
      ),
      bandId: band.id,
      bandLabel: band.label,
      samplesUsed: costs.length,
    };
  }

  // Conditions guard. The baseline is only comparable if it was built in
  // conditions this session shares — see HEAT_OUT_OF_RANGE_F.
  const sessionHeat = sampleHeatIndex(session);
  const poolHeat = pool.map(sampleHeatIndex).filter((h): h is number => h != null);
  if (sessionHeat != null && poolHeat.length >= MIN_SAMPLES) {
    const poolMedian = median(poolHeat);
    const spread = madSigma(poolHeat);
    const allowed = Math.max(
      HEAT_OUT_OF_RANGE_F,
      HEAT_OUT_OF_RANGE_SIGMA * (isFinite(spread) ? spread : 0),
    );
    const gap = Math.abs(sessionHeat - poolMedian);
    if (gap > allowed) {
      return {
        ...empty(
          `conditions too different to compare — ${Math.round(sessionHeat)}\u00B0F apparent vs a baseline built around ${Math.round(poolMedian)}\u00B0F`,
          round1(cost),
        ),
        bandId: band.id,
        bandLabel: band.label,
        samplesUsed: costs.length,
      };
    }
  }

  const baseline = median(costs);
  const sigma = Math.max(madSigma(costs), baseline * SIGMA_FLOOR_PCT);
  const z = (cost - baseline) / sigma;
  const deltaPct = ((cost - baseline) / baseline) * 100;

  let verdict: Verdict = "nothing-detected";
  if (z >= Z_VERY_ELEVATED) verdict = "very-elevated";
  else if (z >= Z_ELEVATED) verdict = "elevated";
  else if (z <= -Z_ELEVATED) verdict = "lower-than-usual";

  return {
    cost: round1(cost),
    bandId: band.id,
    bandLabel: band.label,
    baseline: round1(baseline),
    sigma: round1(sigma),
    z: round2(z),
    deltaPct: round1(deltaPct),
    verdict,
    blockedBy: null,
    samplesUsed: costs.length,
    // A read built on runs whose climb we do not know is a weaker read: the
    // uncorrected hill is worth more bpm than the thing being measured.
    confidence: session.elevationGainMetersPerMile == null
      ? "low"
      : costs.length >= STRONG_SAMPLES
      ? "high"
      : "moderate",
  };
}

// ── Load adjustment ─────────────────────────────────────────────────────────

/**
 * Fraction of the cardiac-cost excursion that is allowed to move a load score.
 * 0.4, not 1.0, on purpose: cost residuals carry ~2.7% of pure noise (3.9 bpm
 * on ~145), and half-crediting the excursion keeps a noise-sized wobble under
 * ~1% of TLS while a real +8% excursion still registers as ~+3%.
 */
export const HR_ADJUST_GAIN = 0.4;
/** Hard cap on how far HR evidence may move a load score, either direction. */
export const HR_ADJUST_MAX = 0.06;

/**
 * Multiplier a pace-based load score (TLS, effort_load) should be scaled by,
 * given this session's cardiac-cost read. The pace model prices the work; this
 * nudges the price by what the work measurably COST — same pace at a heart
 * rate 6% above this athlete's own baseline was a harder session than the
 * pace alone admits, and vice versa.
 *
 * Deliberately gentle and self-limiting:
 *   • no read (thin baseline, no HR, cooldown, conditions guard) → exactly 1.0
 *     — the pace score stands alone, which is what it did before this existed;
 *   • bounded to ±HR_ADJUST_MAX so a chest-strap dropout spike can never
 *     double a run's load;
 *   • inherits every guard the read has (daypart matching, climb correction,
 *     heat out-of-range refusal), so the failure modes that would distort it
 *     produce 1.0 instead of a wrong number.
 */
export function hrEffortMultiplier(r: RecoveryRead): number {
  if (r.verdict === "no-read" || r.deltaPct == null || !isFinite(r.deltaPct)) return 1;
  const adj = HR_ADJUST_GAIN * (r.deltaPct / 100);
  const clamped = Math.max(-HR_ADJUST_MAX, Math.min(HR_ADJUST_MAX, adj));
  return Math.round((1 + clamped) * 1000) / 1000;
}

/**
 * Plain-language line for a read. Facts and a range — never a recommendation,
 * never "you need another rest day". The athlete does the interpreting; this
 * does the noticing.
 */
export function describeRead(r: RecoveryRead): string {
  if (r.verdict === "no-read") return r.blockedBy ?? "No read available.";
  const pct = Math.abs(r.deltaPct ?? 0).toFixed(1);
  const band = (r.bandLabel ?? "this pace").toLowerCase();
  switch (r.verdict) {
    case "very-elevated":
      return `${pct}% more beats per mile than your usual ${band} run — well outside your normal spread (${r.samplesUsed} sessions).`;
    case "elevated":
      return `${pct}% more beats per mile than your usual ${band} run — outside your normal spread (${r.samplesUsed} sessions).`;
    case "lower-than-usual":
      return `${pct}% fewer beats per mile than your usual ${band} run (${r.samplesUsed} sessions).`;
    default:
      return `Within your normal spread for ${band} running (${r.samplesUsed} sessions).`;
  }
}

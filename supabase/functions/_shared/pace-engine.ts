/**
 * PaceEngine — the single source of truth for an athlete's pace zones.
 *
 * BEFORE THIS FILE: pace logic lived in 7+ places that disagreed.
 *   - iOS PaceCalculator.calculateTrainingPaces  (mp × 1.18 — DELETED)
 *   - iOS PaceModels.derivedZones                (mp × 1.175 — too fast, the bug)
 *   - _shared/pace-zones.ts                      (mp + 90 — additive)
 *   - _shared/athlete-state.ts                   (mp × 1.28 legacy + DB-direct + derived)
 *   - _shared/paces.ts                           (RACE_RATIOS_TO_10K cascade)
 *   - _shared/pace_adjuster.ts                   (slow-adjusting from real runs, isolated)
 *   - _shared/resolve-pace.ts                    (DB reader for athlete_pace_profiles)
 *
 * Same athlete, three different "easy" paces depending which path fired.
 *
 * AFTER THIS FILE: every consumer (iOS, edge functions, AI prompts, plan
 * generation, analytics) calls computePaceZones. There is no other place
 * that does pace math. If a value is wrong here, it is wrong everywhere —
 * which is the point.
 *
 * Output shape mirrors the canonical iOS PaceChartView:
 *   - 3 training-pace ranges: Easy / Moderate / Steady (effort %)
 *   - Race anchors: marathon, halfMarathon, tenMile, tenK, fiveK, threeK,
 *     mile, fifteenHundred
 *   - observedEasy diagnostic: where the athlete actually ran easy
 *
 * Multipliers below are the COACH'S calibration — NOT Daniels VDOT, NOT
 * Pfitzinger zones. Easy is a *definition* (MP × 1.20–1.30, contiguous with
 * Moderate), not a measurement. Observed run data is reported alongside as
 * a diagnostic but never reshapes the band — an athlete running easy too
 * fast should be flagged, not have their zone redefined to fit the bad
 * behavior.
 */

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

// ── Public types ─────────────────────────────────────────

export type PaceSource =
  | "observed"     // legacy: was used when observed paces overrode the band.
                   // No longer emitted — observed surfaces via observedEasy
                   // diagnostic instead. Kept in the union for decoder
                   // backwards-compat with cached payloads.
  | "profile"      // athlete_pace_profiles DB row
  | "race_derived" // anchored to fitness_snapshots predictions
  | "goal_only"    // training_plans.target_time_seconds, nothing else
  | "none";        // no data at all

export type Confidence = "high" | "medium" | "low" | "none";

/**
 * A pace range. Lower seconds/mi = faster.
 *   paceFast = fastest pace in the range (drift faster → out of zone)
 *   paceSlow = slowest pace in the range (drift slower → out of zone)
 *
 * For Easy specifically, paceSlow is set to a sanity-rail ceiling
 * because the chart's framing is "75% effort OR LESS" — there is no
 * upper bound on slowness. Render layers should display Easy as
 * "{paceFast}+/mi" (open-ended).
 */
export interface PaceRange {
  paceFast: number;        // sec/mi, fastest bound
  paceSlow: number;        // sec/mi, slowest bound (Easy: sanity rail)
  label: string;           // chart label, e.g. "Easy"
  effortPercent: string;   // chart subtitle, e.g. "75% effort or less"
  openEndedSlow: boolean;  // true for Easy — render as "{paceFast}+/mi"
  source: PaceSource;
  confidence: Confidence;
}

/** A race target — single anchor pace. */
export interface PaceAnchor {
  pace: number;            // sec/mi
  source: PaceSource;
  confidence: Confidence;
}

/**
 * Snapshot of where the athlete *actually* ran easy in the lookback window.
 * Diagnostic only — the Easy zone itself is always doctrine-derived
 * (MP × 1.20–1.30). Compare this to `easy` to see whether the athlete is
 * holding the line on easy effort. If `paceFast` is faster than
 * `easy.paceFast`, the athlete is running easy too hot.
 */
export interface ObservedEasySnapshot {
  paceFast: number;     // sec/mi, p25 of recent easy/recovery/long_run paces
  paceSlow: number;     // sec/mi, p75
  sessionCount: number;
  lookbackDays: number;
}

export interface PaceZones {
  // Training-pace ranges (the canonical chart's range zones).
  // ALWAYS doctrine-derived from MP × multipliers. Bands are exact %-of-MP
  // speed, contiguous (no gaps). Easy is a definition, not a measurement.
  // To see what the athlete actually runs easy, read observedEasy below.
  recovery: PaceRange | null; // < 70% MP speed (open-ended slow side)
  easy:     PaceRange | null; // 70-80% MP speed
  moderate: PaceRange | null; // 80-90% MP speed
  steady:   PaceRange | null; // 90-100% MP speed

  // Race anchors (the canonical chart's exact-pace zones).
  // The chart's 10-zone spectrum is: recovery, easy, moderate, steady,
  // marathon, halfMarathon, tenK, fiveK, threeK, mile.
  marathon:       PaceAnchor | null; // also rendered as "MP"
  halfMarathon:   PaceAnchor | null; // also rendered as "HMP"
  tenK:           PaceAnchor | null;
  fiveK:          PaceAnchor | null;
  threeK:         PaceAnchor | null;
  mile:           PaceAnchor | null;

  // Off-spectrum anchors retained for legacy consumers (FitnessPredictor,
  // race-readiness). Not displayed on the canonical chart.
  tenMile:        PaceAnchor | null;
  fifteenHundred: PaceAnchor | null;

  // Diagnostic: where the athlete actually ran easy. Null when fewer than
  // OBSERVED_MIN_SESSIONS easy runs in the lookback window. The Easy zone
  // is NOT derived from this — it's purely a "are they holding the line?"
  // signal for the coach.
  observedEasy: ObservedEasySnapshot | null;

  // Diagnostic envelope.
  athleteUserId: string;
  computedAt: string;        // ISO timestamp
  primarySource: PaceSource; // best source actually used
}

// ── Inputs (pre-fetched data) ────────────────────────────

export interface AthletePaceProfileRow {
  easy_pace_seconds: number | null;
  marathon_pace_seconds: number | null;
  half_pace_seconds: number | null;
  ten_k_pace_seconds: number | null;
  five_k_pace_seconds: number | null;
  mile_pace_seconds: number | null;
  updated_at: string;
}

export interface FitnessSnapshotRow {
  predicted_5k_seconds: number | null;
  predicted_10k_seconds: number | null;
  predicted_half_seconds: number | null;
  predicted_marathon_seconds: number | null;
  predicted_mile_seconds: number | null;
  created_at: string;
}

export interface TrainingPlanRow {
  target_race_distance: string | null;
  target_time_seconds: number | null;
}

export interface TrainingLogRow {
  workout_date: string;
  workout_distance_miles: number | null;
  workout_duration_minutes: number | null;
  workout_pace_per_mile: string | null; // "M:SS"
  workout_type: string | null;
  parsed_structure: { type?: string } | null;
  source: string | null;
}

export interface PaceEngineInput {
  athleteUserId: string;
  profile: AthletePaceProfileRow | null;
  snapshot: FitnessSnapshotRow | null;
  plan: TrainingPlanRow | null;
  recentLogs: TrainingLogRow[];
  now?: Date;
}

// ── Tunable constants ────────────────────────────────────

/**
 * Training-pace multipliers on MP. THE CANONICAL CALIBRATION.
 *
 * Bands are exact "% of MP speed" — multipliers are reciprocals of the
 * speed fraction, not approximations:
 *   100% MP speed = 1.0   × MP pace
 *    90% MP speed = 1.111 × MP pace  (1 / 0.9)
 *    80% MP speed = 1.25  × MP pace  (1 / 0.8)
 *    70% MP speed = 1.429 × MP pace  (1 / 0.7)
 *    60% MP speed = 1.667 × MP pace  (1 / 0.6)  — recovery floor
 *
 * Bands are contiguous (no gaps, no overlaps):
 *   Recovery.fast  = Easy.slow      = 1.4286
 *   Easy.fast      = Moderate.slow  = 1.25
 *   Moderate.fast  = Steady.slow    = 1.1111
 *   Steady.fast    = MP itself      = 1.0
 *
 * Source of truth — every surface (iOS PaceModels.NamedPace, web pace
 * editor, training-tab display) reads through this file.
 */
export const TRAINING_PACE_MULTIPLIERS = {
  recovery: {
    fast: 1.4286, // 70% MP speed — fastest acceptable recovery (= easy.slow)
    slow: 1.6667, // 60% MP speed — slowest practical recovery
  },
  easy: {
    fast: 1.25,   // 80% MP speed — fastest acceptable easy
    slow: 1.4286, // 70% MP speed — slowest acceptable easy
  },
  moderate: {
    fast: 1.1111, // 90% MP speed — fastest acceptable moderate
    slow: 1.25,   // 80% MP speed — slowest acceptable moderate
  },
  steady: {
    fast: 1.0,    // 100% MP speed — fastest acceptable steady (= MP)
    slow: 1.1111, // 90% MP speed — slowest acceptable steady
  },
} as const;

/** "% of MP speed" labels rendered in the chart. */
const EFFORT_LABELS = {
  recovery: { label: "Recovery", effortPercent: "<70% MP" },
  easy:     { label: "Easy",     effortPercent: "70-80% MP" },
  moderate: { label: "Moderate", effortPercent: "80-90% MP" },
  steady:   { label: "Steady",   effortPercent: "90-100% MP" },
} as const;

/** Floor and ceiling on any returned pace, sec/mi. */
const PACE_FLOOR_SEC = 180;    // 3:00/mi
const PACE_CEILING_SEC = 1200; // 20:00/mi

/** Minimum logged easy runs to use observed paces over derived. */
const OBSERVED_MIN_SESSIONS = 8;
const OBSERVED_LOOKBACK_DAYS = 90;

// Race distances in miles.
const MILES = {
  fifteenHundred: 0.93205678836,  // 1500m
  mile: 1.0,
  threeK: 1.86411358,             // 3000m
  fiveK: 3.10685596,
  tenK: 6.21371192,
  tenMile: 10.0,
  halfMarathon: 13.10937544,
  marathon: 26.21875088,
} as const;

// ── Public API ───────────────────────────────────────────

export function computePaceZones(input: PaceEngineInput): PaceZones {
  const now = input.now ?? new Date();

  const raceAnchors = resolveRaceAnchors(input);
  const observedEasyRange = computeObservedEasyRange(input.recentLogs, now);
  const trainingZones = resolveTrainingZones(raceAnchors.marathon);

  const observedEasy: ObservedEasySnapshot | null = observedEasyRange
    ? {
      paceFast: observedEasyRange.paceFast,
      paceSlow: observedEasyRange.paceSlow,
      sessionCount: observedEasyRange.sessionCount,
      lookbackDays: OBSERVED_LOOKBACK_DAYS,
    }
    : null;

  const primarySource: PaceSource = input.profile && hasAnyProfilePace(input.profile)
    ? "profile"
    : input.snapshot && hasAnySnapshotPrediction(input.snapshot)
    ? "race_derived"
    : input.plan?.target_time_seconds && input.plan?.target_race_distance
    ? "goal_only"
    : "none";

  return {
    recovery: trainingZones.recovery,
    easy:     trainingZones.easy,
    moderate: trainingZones.moderate,
    steady:   trainingZones.steady,

    marathon:       raceAnchors.marathon,
    halfMarathon:   raceAnchors.halfMarathon,
    tenK:           raceAnchors.tenK,
    fiveK:          raceAnchors.fiveK,
    threeK:         raceAnchors.threeK,
    mile:           raceAnchors.mile,

    tenMile:        raceAnchors.tenMile,
    fifteenHundred: raceAnchors.fifteenHundred,

    observedEasy,

    athleteUserId: input.athleteUserId,
    computedAt: now.toISOString(),
    primarySource,
  };
}

/**
 * Async wrapper: fetches the four source tables and computes the zones.
 * Use from edge functions that don't already have the data on hand.
 */
export async function fetchAndComputePaceZones(
  supabase: SupabaseClient,
  userId: string,
): Promise<PaceZones> {
  const ninetyDaysAgo = new Date(Date.now() - OBSERVED_LOOKBACK_DAYS * 86400000)
    .toISOString();

  const [profileRes, snapshotRes, planRes, logsRes] = await Promise.all([
    supabase
      .from("athlete_pace_profiles")
      .select(
        "easy_pace_seconds, marathon_pace_seconds, half_pace_seconds, ten_k_pace_seconds, five_k_pace_seconds, mile_pace_seconds, updated_at",
      )
      .eq("user_id", userId)
      .maybeSingle(),
    supabase
      .from("fitness_snapshots")
      .select(
        "predicted_5k_seconds, predicted_10k_seconds, predicted_half_seconds, predicted_marathon_seconds, predicted_mile_seconds, created_at",
      )
      .eq("user_id", userId)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle(),
    supabase
      .from("training_plans")
      .select("target_race_distance, target_time_seconds")
      .eq("user_id", userId)
      .eq("status", "active")
      .maybeSingle(),
    supabase
      .from("training_logs")
      .select(
        "workout_date, workout_distance_miles, workout_duration_minutes, workout_pace_per_mile, workout_type, parsed_structure, source",
      )
      .eq("user_id", userId)
      .gte("workout_date", ninetyDaysAgo)
      .order("workout_date", { ascending: false })
      .limit(400),
  ]);

  return computePaceZones({
    athleteUserId: userId,
    profile: profileRes.data as AthletePaceProfileRow | null,
    snapshot: snapshotRes.data as FitnessSnapshotRow | null,
    plan: planRes.data as TrainingPlanRow | null,
    recentLogs: (logsRes.data ?? []) as TrainingLogRow[],
  });
}

// ── Internals ────────────────────────────────────────────

interface RaceAnchorTable {
  marathon:       PaceAnchor | null;
  halfMarathon:   PaceAnchor | null;
  tenMile:        PaceAnchor | null;
  tenK:           PaceAnchor | null;
  fiveK:          PaceAnchor | null;
  threeK:         PaceAnchor | null;
  mile:           PaceAnchor | null;
  fifteenHundred: PaceAnchor | null;
}

function resolveRaceAnchors(input: PaceEngineInput): RaceAnchorTable {
  const { profile, snapshot } = input;

  const buildAnchor = (
    profileVal: number | null | undefined,
    snapshotVal: number | null | undefined,
  ): PaceAnchor | null => {
    if (profileVal != null && profileVal >= PACE_FLOOR_SEC && profileVal <= PACE_CEILING_SEC) {
      return { pace: Math.round(profileVal), source: "profile", confidence: "high" };
    }
    if (snapshotVal != null && snapshotVal > 0) {
      return { pace: Math.round(snapshotVal), source: "race_derived", confidence: "medium" };
    }
    return null;
  };

  let marathon = buildAnchor(
    profile?.marathon_pace_seconds,
    snapshotPace(snapshot?.predicted_marathon_seconds, MILES.marathon),
  );
  const halfMarathon = buildAnchor(
    profile?.half_pace_seconds,
    snapshotPace(snapshot?.predicted_half_seconds, MILES.halfMarathon),
  );
  const tenK = buildAnchor(
    profile?.ten_k_pace_seconds,
    snapshotPace(snapshot?.predicted_10k_seconds, MILES.tenK),
  );
  const fiveK = buildAnchor(
    profile?.five_k_pace_seconds,
    snapshotPace(snapshot?.predicted_5k_seconds, MILES.fiveK),
  );
  const mile = buildAnchor(
    profile?.mile_pace_seconds,
    snapshotPace(snapshot?.predicted_mile_seconds, MILES.mile),
  );

  // Goal-only fallback for marathon — when no profile, no snapshot, but
  // the athlete has set a target time on an active plan.
  if (!marathon && input.plan?.target_time_seconds && input.plan?.target_race_distance) {
    const goalPace = goalToMpPace(input.plan);
    if (goalPace) {
      marathon = { pace: Math.round(goalPace), source: "goal_only", confidence: "low" };
    }
  }

  // 10 Mile, 3K, 1500m: derive from neighboring anchors via simple cascades.
  // These aren't stored in profile or snapshot — they're chart-display-only.
  const tenMile = deriveCascade(tenK, halfMarathon, "tenMile");
  const threeK  = deriveCascade(fiveK, mile, "threeK");
  const fifteenHundred = deriveCascade(mile, threeK, "fifteenHundred");

  return { marathon, halfMarathon, tenMile, tenK, fiveK, threeK, mile, fifteenHundred };
}

/**
 * Derive one of the "in-between" race anchors (10mi, 3K, 1500m) from its
 * neighbors. Confidence is one tier lower than the source. Cascade only —
 * no formulas, no multipliers beyond simple distance scaling.
 */
function deriveCascade(
  faster: PaceAnchor | null,
  slower: PaceAnchor | null,
  target: "tenMile" | "threeK" | "fifteenHundred",
): PaceAnchor | null {
  // Performance-ratio scaling. The "fromFaster"/"fromSlower" naming refers
  // to the source race anchor's preferred priority, not its pace. For 3K,
  // 5K is preferred (more reliable as a source) even though mile pace is
  // faster per mile. Tuned to coach intuition — 3K from 5K ≈ 4% faster.
  const ratios: Record<string, { fromFaster: number; fromSlower: number }> = {
    tenMile:        { fromFaster: 1.025, fromSlower: 0.97  }, // 10K +2.5%, HM −3%
    threeK:         { fromFaster: 0.96,  fromSlower: 1.045 }, // 5K −4%, mile +4.5%
    fifteenHundred: { fromFaster: 0.99,  fromSlower: 0.94  }, // mile −1%, 3K −6%
  };
  const r = ratios[target];

  if (faster) {
    return { pace: Math.round(faster.pace * r.fromFaster), source: faster.source, confidence: stepDownConfidence(faster.confidence) };
  }
  if (slower) {
    return { pace: Math.round(slower.pace * r.fromSlower), source: slower.source, confidence: stepDownConfidence(slower.confidence) };
  }
  return null;
}

function stepDownConfidence(c: Confidence): Confidence {
  return c === "high" ? "medium" : c === "medium" ? "low" : c;
}

function snapshotPace(totalSeconds: number | null | undefined, miles: number): number | null {
  if (totalSeconds == null || totalSeconds <= 0) return null;
  return totalSeconds / miles;
}

function goalToMpPace(plan: TrainingPlanRow): number | null {
  if (!plan.target_time_seconds || !plan.target_race_distance) return null;
  const distMi = distanceFromKey(plan.target_race_distance);
  if (!distMi) return null;
  const pace = plan.target_time_seconds / distMi;
  if (pace < PACE_FLOOR_SEC || pace > PACE_CEILING_SEC) return null;
  if (distMi >= MILES.marathon - 0.1) return pace;
  if (distMi >= MILES.halfMarathon - 0.1) return pace * 1.06;
  if (distMi >= MILES.tenK - 0.1) return pace * 1.15;
  if (distMi >= MILES.fiveK - 0.1) return pace * 1.22;
  return pace * 1.30;
}

function distanceFromKey(key: string): number | null {
  const k = key.toLowerCase().trim();
  if (k === "marathon") return MILES.marathon;
  if (k === "half" || k === "half_marathon" || k === "half marathon" || k === "hm") return MILES.halfMarathon;
  if (k === "10mi" || k === "10_mile" || k === "10 mile") return MILES.tenMile;
  if (k === "10k" || k === "ten_k") return MILES.tenK;
  if (k === "5k" || k === "five_k") return MILES.fiveK;
  if (k === "3k" || k === "three_k") return MILES.threeK;
  if (k === "mile") return MILES.mile;
  if (k === "1500m" || k === "1500") return MILES.fifteenHundred;
  return null;
}

interface TrainingZoneTable {
  recovery: PaceRange | null;
  easy:     PaceRange | null;
  moderate: PaceRange | null;
  steady:   PaceRange | null;
}

interface ObservedEasy {
  paceFast: number;
  paceSlow: number;
  sessionCount: number;
}

/**
 * Build Easy / Moderate / Steady from MP. Always doctrine — multipliers,
 * not athlete behavior. If MP itself is null, return all-null. The Easy
 * zone is intentionally NOT touched by observed run data; observed paces
 * are surfaced separately as a diagnostic via `observedEasy`.
 */
function resolveTrainingZones(marathon: PaceAnchor | null): TrainingZoneTable {
  if (!marathon) {
    return { recovery: null, easy: null, moderate: null, steady: null };
  }
  const mp = marathon.pace;
  const sourceLabel: PaceSource =
    marathon.source === "goal_only" ? "goal_only" : "race_derived";
  const confidence: Confidence =
    marathon.source === "profile" ? "high"
    : marathon.source === "race_derived" ? "medium"
    : "low";

  const buildRange = (
    key: keyof typeof TRAINING_PACE_MULTIPLIERS,
    openEndedSlow = false,
  ): PaceRange => ({
    paceFast: clampPace(mp * TRAINING_PACE_MULTIPLIERS[key].fast),
    paceSlow: clampPace(mp * TRAINING_PACE_MULTIPLIERS[key].slow),
    label: EFFORT_LABELS[key].label,
    effortPercent: EFFORT_LABELS[key].effortPercent,
    openEndedSlow,
    source: sourceLabel,
    confidence,
  });

  return {
    // Recovery is open-ended on the slow side — anything slower than 70% MP
    // counts. The 1.6667 (60% MP) is a practical floor for the chart, not
    // a hard cap on what the athlete might run.
    recovery: buildRange("recovery", true),
    easy:     buildRange("easy"),
    moderate: buildRange("moderate"),
    steady:   buildRange("steady"),
  };
}

function computeObservedEasyRange(
  logs: TrainingLogRow[],
  now: Date,
): ObservedEasy | null {
  const cutoff = new Date(now.getTime() - OBSERVED_LOOKBACK_DAYS * 86400000);
  const easyTypes = new Set(["easy", "recovery", "long_run"]);
  const excludeTypes = new Set(["race", "interval", "intervals", "tempo", "progression"]);

  const paces: number[] = [];
  for (const log of logs) {
    if (!log.workout_date) continue;
    if (new Date(log.workout_date) < cutoff) continue;

    const parsedType = log.parsed_structure?.type;
    const rawType = log.workout_type;
    if (parsedType && excludeTypes.has(parsedType)) continue;
    const effectiveType = parsedType ?? rawType;
    if (!effectiveType || !easyTypes.has(effectiveType)) continue;

    const dist = log.workout_distance_miles;
    if (!dist || dist < 1) continue;

    let paceSec: number | null = null;
    if (log.workout_pace_per_mile) {
      paceSec = parsePace(log.workout_pace_per_mile);
    }
    if (paceSec == null && log.workout_duration_minutes && dist) {
      paceSec = (log.workout_duration_minutes * 60) / dist;
    }
    if (paceSec == null) continue;
    if (paceSec < PACE_FLOOR_SEC || paceSec > PACE_CEILING_SEC) continue;

    paces.push(paceSec);
  }

  if (paces.length < OBSERVED_MIN_SESSIONS) return null;

  paces.sort((a, b) => a - b);
  const p25 = quantile(paces, 0.25);
  const p75 = quantile(paces, 0.75);

  return {
    paceFast: Math.round(p25),
    paceSlow: Math.round(p75),
    sessionCount: paces.length,
  };
}

function quantile(sorted: number[], q: number): number {
  if (sorted.length === 0) return 0;
  const idx = (sorted.length - 1) * q;
  const lo = Math.floor(idx);
  const hi = Math.ceil(idx);
  if (lo === hi) return sorted[lo];
  return sorted[lo] + (idx - lo) * (sorted[hi] - sorted[lo]);
}

function parsePace(s: string): number | null {
  const m = s.match(/^(\d{1,2}):(\d{2})$/);
  if (!m) return null;
  const min = parseInt(m[1]);
  const sec = parseInt(m[2]);
  if (isNaN(min) || isNaN(sec)) return null;
  return min * 60 + sec;
}

function clampPace(sec: number): number {
  return Math.max(PACE_FLOOR_SEC, Math.min(PACE_CEILING_SEC, Math.round(sec)));
}

function hasAnyProfilePace(p: AthletePaceProfileRow): boolean {
  return !!(
    p.easy_pace_seconds ||
    p.marathon_pace_seconds ||
    p.half_pace_seconds ||
    p.ten_k_pace_seconds ||
    p.five_k_pace_seconds ||
    p.mile_pace_seconds
  );
}

function hasAnySnapshotPrediction(s: FitnessSnapshotRow): boolean {
  return !!(
    s.predicted_5k_seconds ||
    s.predicted_10k_seconds ||
    s.predicted_half_seconds ||
    s.predicted_marathon_seconds ||
    s.predicted_mile_seconds
  );
}

// ── Legacy projection ────────────────────────────────────
//
// Several consumers (post-run-analysis, training-analysis, workoutSelection)
// were written against a flat numeric pace-zones shape pre-engine. They need
// `{ easy, moderate, steady, marathon, halfMarathon, threshold, tenK, fiveK }`
// — single numbers, not ranges. Until they're refactored to consume engine
// output directly, this helper projects engine PaceZones into that shape.
//
// Recovery / Easy / Moderate / Steady use the MIDPOINT of each band as the
// single anchor. The legacy `threshold` and `longRun` zones were dropped
// when the canonical chart was simplified to one spectrum — HMP covers
// threshold effort, easy covers long-run pace.

export interface LegacyPaceZones {
  recovery: number;      // sec/mi, midpoint of recovery band (~65% MP)
  easy: number;          // sec/mi, midpoint of easy band (~75% MP)
  moderate: number;      // sec/mi, midpoint of moderate band (~85% MP)
  steady: number;        // sec/mi, midpoint of steady band (~95% MP)
  marathon: number;      // sec/mi
  halfMarathon: number;  // sec/mi
  tenK: number;          // sec/mi
  fiveK: number;         // sec/mi
  threeK: number;        // sec/mi
  mile: number;          // sec/mi
}

/**
 * Project engine PaceZones to the legacy flat shape used by consumers that
 * haven't been refactored to read ranges yet. Returns null when the engine
 * couldn't derive any zones (no MP / HM / 10K / 5K source data).
 */
export function projectToLegacyZones(zones: PaceZones): LegacyPaceZones | null {
  const mpAnchor = zones.marathon?.pace ?? 0;
  const hmAnchor = zones.halfMarathon?.pace ?? 0;
  const tkAnchor = zones.tenK?.pace ?? 0;
  const fkAnchor = zones.fiveK?.pace ?? 0;

  if (!mpAnchor && !hmAnchor && !tkAnchor && !fkAnchor) return null;

  // Engine cascades fill these in when one race anchor is present, but keep
  // belt-and-suspenders fallbacks for completeness.
  const mp = mpAnchor || (hmAnchor * 1.06) || (tkAnchor * 1.15) || (fkAnchor * 1.22);
  const hm = hmAnchor || (mpAnchor * 0.943) || (tkAnchor * 1.08) || (fkAnchor * 1.15);
  const tk = tkAnchor || (hmAnchor * 0.925) || (fkAnchor * 1.06) || (mp * 0.87);
  const fk = fkAnchor || (tkAnchor * 0.943) || (hmAnchor * 0.87) || (mp * 0.82);

  // Single-number anchors per zone — midpoint of each band.
  // For 2:20 marathoner (mp 320): recovery=485 (8:05), easy=427 (7:07),
  // moderate=378 (6:18), steady=338 (5:38).
  const recovery = zones.recovery
    ? (zones.recovery.paceFast + zones.recovery.paceSlow) / 2
    : mp * 1.5476; // 65% MP fallback (midpoint of 60-70%)
  const easy = zones.easy
    ? (zones.easy.paceFast + zones.easy.paceSlow) / 2
    : mp * 1.3393; // 75% MP fallback (midpoint of 70-80%)
  const moderate = zones.moderate
    ? (zones.moderate.paceFast + zones.moderate.paceSlow) / 2
    : mp * 1.1806; // 85% MP fallback (midpoint of 80-90%)
  const steady = zones.steady
    ? (zones.steady.paceFast + zones.steady.paceSlow) / 2
    : mp * 1.0556; // 95% MP fallback (midpoint of 90-100%)

  // 3K and mile cascade off the race anchors (or fall back to ratios).
  const threeKAnchor = zones.threeK?.pace ?? 0;
  const mileAnchor = zones.mile?.pace ?? 0;
  const threeK = threeKAnchor || (fk * 0.95);
  const mile = mileAnchor || (threeKAnchor ? threeKAnchor * 0.93 : fk * 0.88);

  return {
    recovery: Math.round(recovery),
    easy: Math.round(easy),
    moderate: Math.round(moderate),
    steady: Math.round(steady),
    marathon: Math.round(mp),
    halfMarathon: Math.round(hm),
    tenK: Math.round(tk),
    fiveK: Math.round(fk),
    threeK: Math.round(threeK),
    mile: Math.round(mile),
  };
}

/**
 * Convenience: build a snapshot-only engine input and project to the legacy
 * shape in one call. Used by consumers that have only a fitness_snapshots
 * row in scope (not a full athlete context).
 */
export function legacyZonesFromSnapshot(snap: {
  predicted_5k_seconds?: number | null;
  predicted_10k_seconds?: number | null;
  predicted_half_seconds?: number | null;
  predicted_marathon_seconds?: number | null;
  predicted_mile_seconds?: number | null;
}): LegacyPaceZones | null {
  const zones = computePaceZones({
    athleteUserId: "",
    profile: null,
    snapshot: {
      predicted_5k_seconds: snap.predicted_5k_seconds ?? null,
      predicted_10k_seconds: snap.predicted_10k_seconds ?? null,
      predicted_half_seconds: snap.predicted_half_seconds ?? null,
      predicted_marathon_seconds: snap.predicted_marathon_seconds ?? null,
      predicted_mile_seconds: snap.predicted_mile_seconds ?? null,
      created_at: new Date().toISOString(),
    },
    plan: null,
    recentLogs: [],
  });
  return projectToLegacyZones(zones);
}

/**
 * Range form of the effort-zone output for snapshot-only callers. Used by
 * prompt builders (post-run-analysis, training-analysis) that want to render
 * Easy / Moderate / Steady / HMP as bands instead of midpoints.
 */
export interface PaceZoneRanges {
  easy?:     { paceFast: number; paceSlow: number; effortPercent: string };
  moderate?: { paceFast: number; paceSlow: number; effortPercent: string };
  steady?:   { paceFast: number; paceSlow: number; effortPercent: string };
  hmp?:      { paceFast: number; paceSlow: number; effortPercent: string };
}

export function rangesFromSnapshot(snap: {
  predicted_5k_seconds?: number | null;
  predicted_10k_seconds?: number | null;
  predicted_half_seconds?: number | null;
  predicted_marathon_seconds?: number | null;
  predicted_mile_seconds?: number | null;
}): PaceZoneRanges {
  const zones = computePaceZones({
    athleteUserId: "",
    profile: null,
    snapshot: {
      predicted_5k_seconds: snap.predicted_5k_seconds ?? null,
      predicted_10k_seconds: snap.predicted_10k_seconds ?? null,
      predicted_half_seconds: snap.predicted_half_seconds ?? null,
      predicted_marathon_seconds: snap.predicted_marathon_seconds ?? null,
      predicted_mile_seconds: snap.predicted_mile_seconds ?? null,
      created_at: new Date().toISOString(),
    },
    plan: null,
    recentLogs: [],
  });
  const out: PaceZoneRanges = {};
  if (zones.easy) {
    out.easy = {
      paceFast: zones.easy.paceFast,
      paceSlow: zones.easy.paceSlow,
      effortPercent: zones.easy.effortPercent,
    };
  }
  if (zones.moderate) {
    out.moderate = {
      paceFast: zones.moderate.paceFast,
      paceSlow: zones.moderate.paceSlow,
      effortPercent: zones.moderate.effortPercent,
    };
  }
  if (zones.steady) {
    out.steady = {
      paceFast: zones.steady.paceFast,
      paceSlow: zones.steady.paceSlow,
      effortPercent: zones.steady.effortPercent,
    };
  }
  if (zones.halfMarathon) {
    const a = zones.halfMarathon.pace;
    out.hmp = { paceFast: a - 5, paceSlow: a + 5, effortPercent: "Half Marathon Pace" };
  }
  return out;
}

// ── Formatters (canonical chart-style strings) ──────────

export function formatPace(sec: number): string {
  const m = Math.floor(sec / 60);
  const s = Math.round(sec % 60);
  return `${m}:${String(s).padStart(2, "0")}`;
}

/**
 * Render a training-pace range the way the chart does:
 *   Easy (open-ended):  "6:18+ /mi"
 *   Moderate / Steady:  "5:30 – 5:43 /mi"
 */
export function formatRange(r: PaceRange): string {
  if (r.openEndedSlow) {
    return `${formatPace(r.paceFast)}+ /mi`;
  }
  return `${formatPace(r.paceFast)} – ${formatPace(r.paceSlow)} /mi`;
}

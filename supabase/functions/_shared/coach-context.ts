/**
 * Coach Context — pace anchoring + prescription-vs-execution.
 *
 * Shared module consumed by `process-training-memo` (voice path) and
 * `generate-workout-insight` (HealthKit/manual path). Loads the athlete's
 * canonical pace zones, classifies an executed pace against them, and
 * (when a scheduled_workout is linked) compares prescribed vs. executed.
 *
 * Three artifacts feed into the LLM:
 *   1. A paces block — "## Athlete's training paces" with the canonical
 *      10-zone spectrum, MP-anchored and sourced.
 *   2. A classification line — deterministic, not LLM-derived. Tells the
 *      model what zone the executed pace landed in so it doesn't have to
 *      do the math itself (Flash regularly slips on multi-step pace math).
 *   3. A prescription-vs-execution block — only when a scheduled workout
 *      is linked. Compares per-step prescribed paces to the executed
 *      averages and surfaces deviations in seconds/mile.
 *
 * Each block is opt-in. If a piece is unavailable (no goal, no scheduled
 * workout), the corresponding block is omitted rather than rendered with
 * placeholder values.
 */

import { fetchAndComputePaceZones, PaceZones, PaceAnchor, PaceRange } from "./pace-engine.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

// ── Public surface ───────────────────────────────────────

export interface CoachContext {
  zones: PaceZones | null;
  /** Goal context — race distance, target time, weeks to race. */
  goal: GoalContext | null;
}

export interface GoalContext {
  raceDistance: string;        // e.g. "marathon", "5K"
  targetTimeSeconds: number;
  raceDate: string | null;     // ISO date or null
  weeksToRace: number | null;  // null when raceDate is missing
}

/**
 * Result of classifying a single executed pace against the canonical
 * spectrum. Always deterministic — never an LLM inference. The LLM
 * receives `summary` directly so it doesn't have to compute zones.
 */
export interface PaceClassification {
  paceSecsPerMile: number;
  /** Canonical zone key, or "between"/"faster"/"slower" categorization. */
  bucket:
    | "recovery"
    | "easy"
    | "moderate"
    | "steady"
    | "mp"
    | "hmp"
    | "10K"
    | "5K"
    | "3K"
    | "mile"
    | "faster_than_mile"
    | "slower_than_recovery"
    | "between";
  /** Human-readable summary line — what the LLM sees. */
  summary: string;
}

/**
 * Load the athlete's full coach context. Returns nulls (not throws) when
 * source data is missing, so callers can degrade gracefully.
 */
export async function loadCoachContext(
  supabase: SupabaseClient,
  userId: string,
): Promise<CoachContext> {
  const [zones, goal] = await Promise.all([
    safeLoadZones(supabase, userId),
    safeLoadGoal(supabase, userId),
  ]);
  return { zones, goal };
}

/**
 * Render the paces block as a markdown section the LLM consumes.
 * Returns "" if no zones available — caller should not include the
 * heading in that case.
 */
export function formatPacesBlock(ctx: CoachContext): string {
  if (!ctx.zones) return "";
  const z = ctx.zones;

  const anchorLine = (label: string, anchor: PaceAnchor | null): string =>
    anchor ? `${label}: ${formatPace(anchor.pace)}/mi` : `${label}: —`;

  const rangeLine = (label: string, range: PaceRange | null): string => {
    if (!range) return `${label}: —`;
    if (range.openEndedSlow) {
      return `${label}: ${formatPace(range.paceFast)}+/mi (slower than ${formatPace(range.paceFast)})`;
    }
    return `${label}: ${formatPace(range.paceFast)}-${formatPace(range.paceSlow)}/mi`;
  };

  const lines = [
    rangeLine("Recovery (60-70% MP)", z.recovery),
    rangeLine("Easy (70-80% MP)",     z.easy),
    rangeLine("Moderate (80-90% MP)", z.moderate),
    rangeLine("Steady (90-100% MP)",  z.steady),
    anchorLine("MP",   z.marathon),
    anchorLine("HMP",  z.halfMarathon),
    anchorLine("10K",  z.tenK),
    anchorLine("5K",   z.fiveK),
    anchorLine("3K",   z.threeK),
    anchorLine("Mile", z.mile),
  ];

  let block = `## Athlete's training paces (canonical, MP-anchored)\n${lines.join("\n")}`;

  if (ctx.goal) {
    const time = formatHms(ctx.goal.targetTimeSeconds);
    const weeks = ctx.goal.weeksToRace != null ? ` · ${ctx.goal.weeksToRace}wk to race` : "";
    block += `\n\nGoal: ${time} ${ctx.goal.raceDistance.toLowerCase()}${weeks}`;
  }

  block += `\n\nUse these paces to anchor any zone references in your reading. The classification line below is computed deterministically — trust it over your own pace arithmetic.`;

  return block;
}

/**
 * Classify an executed pace against the canonical zones. Deterministic.
 *
 * Tolerance for race-anchor matches: 5 sec/mi (so 4:42 and 4:38 both
 * count as "5K pace" if 5K is 4:40). Range zones use exact bounds.
 *
 * When the pace falls between two race anchors but isn't in any range,
 * returns "between" with both neighbor names.
 */
export function classifyPace(
  paceSecsPerMile: number,
  zones: PaceZones,
): PaceClassification {
  const P = paceSecsPerMile;
  const TOL = 5;

  // Exact race anchors first (fastest to slowest), with tolerance.
  // We test these BEFORE range zones because steady's fast bound is
  // exactly MP — a pace at MP should report as "MP", not "top of steady".
  const anchors: Array<{ name: PaceClassification["bucket"]; pace: number | null; label: string }> = [
    { name: "mile", pace: zones.mile?.pace ?? null,         label: "mile" },
    { name: "3K",   pace: zones.threeK?.pace ?? null,       label: "3K" },
    { name: "5K",   pace: zones.fiveK?.pace ?? null,        label: "5K" },
    { name: "10K",  pace: zones.tenK?.pace ?? null,         label: "10K" },
    { name: "hmp",  pace: zones.halfMarathon?.pace ?? null, label: "HMP" },
    { name: "mp",   pace: zones.marathon?.pace ?? null,     label: "MP" },
  ];

  for (const a of anchors) {
    if (a.pace != null && Math.abs(P - a.pace) <= TOL) {
      return {
        paceSecsPerMile: P,
        bucket: a.name,
        summary: `Executed ${formatPace(P)}/mi ≈ ${a.label} pace (${formatPace(a.pace)}/mi).`,
      };
    }
  }

  // Faster than mile pace.
  if (zones.mile && P < zones.mile.pace - TOL) {
    return {
      paceSecsPerMile: P,
      bucket: "faster_than_mile",
      summary: `Executed ${formatPace(P)}/mi — faster than mile pace (${formatPace(zones.mile.pace)}/mi). Outside the chart.`,
    };
  }

  // Range zones (steady → moderate → easy → recovery, fastest to slowest).
  if (zones.steady && P >= zones.steady.paceFast && P <= zones.steady.paceSlow) {
    return rangeResult(P, "steady", "Steady", zones.steady);
  }
  if (zones.moderate && P >= zones.moderate.paceFast && P <= zones.moderate.paceSlow) {
    return rangeResult(P, "moderate", "Moderate", zones.moderate);
  }
  if (zones.easy && P >= zones.easy.paceFast && P <= zones.easy.paceSlow) {
    return rangeResult(P, "easy", "Easy", zones.easy);
  }
  if (zones.recovery && P >= zones.recovery.paceFast && P <= zones.recovery.paceSlow) {
    return rangeResult(P, "recovery", "Recovery", zones.recovery);
  }

  // Slower than recovery floor.
  if (zones.recovery && P > zones.recovery.paceSlow) {
    return {
      paceSecsPerMile: P,
      bucket: "slower_than_recovery",
      summary: `Executed ${formatPace(P)}/mi — slower than recovery floor (${formatPace(zones.recovery.paceSlow)}/mi). Likely a walk/jog or warmup pace.`,
    };
  }

  // Between two anchors (no range zone fit). Find the closest neighbors.
  const sortedAnchors = anchors
    .filter((a) => a.pace != null)
    .sort((a, b) => (a.pace! - b.pace!));
  let faster: typeof sortedAnchors[number] | null = null;
  let slower: typeof sortedAnchors[number] | null = null;
  for (const a of sortedAnchors) {
    if (a.pace! < P) faster = a;
    if (a.pace! > P && !slower) slower = a;
  }
  if (faster && slower) {
    return {
      paceSecsPerMile: P,
      bucket: "between",
      summary: `Executed ${formatPace(P)}/mi — between ${faster.label} (${formatPace(faster.pace!)}) and ${slower.label} (${formatPace(slower.pace!)}).`,
    };
  }

  return {
    paceSecsPerMile: P,
    bucket: "between",
    summary: `Executed ${formatPace(P)}/mi — couldn't classify against the chart (insufficient anchors).`,
  };
}

// ── Prescription vs. execution ───────────────────────────

export interface PrescribedExecutedComparison {
  /** Markdown block for the LLM, already formatted. */
  block: string;
  /** True if any step deviated meaningfully from prescription. */
  hasDeviation: boolean;
}

/**
 * When a scheduled workout is linked, compare the prescribed paces to
 * the executed averages step-by-step and surface deviations.
 *
 * Returns null if there's nothing useful to say (no scheduled workout,
 * no parseable structure, no executed paces to compare against).
 */
export function comparePrescribedToExecuted(
  scheduled: ScheduledLite | null,
  executed: ExecutedSummary,
  zones: PaceZones | null,
): PrescribedExecutedComparison | null {
  if (!scheduled) return null;

  const data = scheduled.workout_data ?? {};
  const prescribedName = (data.name ?? scheduled.workout_type ?? "workout") as string;
  const prescribedType = (scheduled.workout_type ?? data.type ?? "") as string;
  const prescribedSteps = parseSteps(data);

  const lines: string[] = [];
  lines.push(`## Prescribed vs. executed`);
  lines.push(`Prescribed: ${prescribedName}${prescribedType ? ` (${prescribedType})` : ""}`);

  let hasDeviation = false;

  // Per-step comparison (only when scheduled has structured steps and
  // executed has matching pace_segments).
  const segments = executed.paceSegments ?? [];
  if (prescribedSteps.length > 0 && segments.length > 0) {
    const matched = matchStepsToSegments(prescribedSteps, segments);
    for (const m of matched) {
      const dev = m.executedSec - m.prescribedSec;
      const sign = dev > 0 ? "+" : "";
      const flag = Math.abs(dev) > 10 ? " ⚠" : ""; // 10s/mi is the threshold for "worth noting"
      if (Math.abs(dev) > 10) hasDeviation = true;
      lines.push(
        `- ${m.label}: prescribed ${formatPace(m.prescribedSec)}/mi, ran ${formatPace(m.executedSec)}/mi (${sign}${dev}s/mi)${flag}`,
      );
    }
  } else if (executed.averagePaceSec != null) {
    // Fallback: compare overall pace vs. prescribed type's expected band.
    const expected = expectedBandForType(prescribedType, zones);
    if (expected) {
      const dev = describeRangeDeviation(executed.averagePaceSec, expected);
      lines.push(`- Overall: ran ${formatPace(executed.averagePaceSec)}/mi · expected ${expected.label} (${expected.summary})`);
      if (dev.outside) hasDeviation = true;
      if (dev.note) lines.push(`  ${dev.note}`);
    }
  }

  if (lines.length <= 2) {
    // Only the heading — nothing useful to add.
    return null;
  }

  return {
    block: lines.join("\n"),
    hasDeviation,
  };
}

// ── Inputs ───────────────────────────────────────────────

export interface ScheduledLite {
  workout_type: string | null;
  workout_data: Record<string, unknown> | null;
}

export interface ExecutedSummary {
  averagePaceSec: number | null;
  paceSegments?: Array<{
    effort?: string;
    pace_per_mile?: string;
    distance_miles?: number;
  }>;
}

// ── Workout progression — find similar prior + compare ───

/**
 * Workout-family map. The matcher groups a current run with prior runs of
 * the same family. Strict workout_type would over-narrow ("tempo" today
 * wouldn't match "progression" three weeks ago, even though they're the
 * same kind of session). Families collapse those into one bucket.
 */
const WORKOUT_FAMILIES: Record<string, string[]> = {
  tempo:     ["tempo", "progression", "threshold"],
  aerobic:   ["easy", "recovery", "long_run"],
  intervals: ["intervals", "interval"],
  race:      ["race"],
  strides:   ["strides"],
};

function familyFor(workoutType: string | null | undefined): string[] | null {
  if (!workoutType) return null;
  const t = workoutType.toLowerCase();
  for (const family of Object.values(WORKOUT_FAMILIES)) {
    if (family.includes(t)) return family;
  }
  return [t]; // unknown type — match exactly
}

export interface PriorWorkout {
  date: string;          // ISO date
  daysAgo: number;
  workoutType: string;
  distanceMiles: number;
  paceSecPerMile: number;
}

export interface CurrentWorkout {
  workoutType: string;
  distanceMiles: number;
  paceSecPerMile: number;
}

/**
 * Find the most-similar prior workout in the same family.
 *
 * Search window: 14-90 days ago. Below 14 days is usually the previous
 * session of the same block (less interesting for progression); beyond
 * 90 days the comparison is weaker because fitness has likely shifted.
 *
 * Distance gate: prior must be within ±50% of current distance. A 4mi
 * tempo isn't a useful comparison for an 8mi tempo (different session
 * shape).
 *
 * Selection: smallest distance delta wins. Ties broken by recency.
 */
export async function findSimilarPriorWorkout(
  supabase: SupabaseClient,
  userId: string,
  current: CurrentWorkout,
  currentDate: Date,
): Promise<PriorWorkout | null> {
  const family = familyFor(current.workoutType);
  if (!family) return null;
  if (!current.distanceMiles || current.distanceMiles <= 0) return null;
  if (!current.paceSecPerMile || current.paceSecPerMile <= 0) return null;

  const lookbackStart = new Date(currentDate.getTime() - 90 * 86400000).toISOString();
  const lookbackEnd = new Date(currentDate.getTime() - 14 * 86400000).toISOString();

  const minDist = current.distanceMiles * 0.5;
  const maxDist = current.distanceMiles * 1.5;

  try {
    const { data, error } = await supabase
      .from("training_logs")
      .select("workout_date, workout_type, workout_distance_miles, workout_pace_per_mile, workout_duration_minutes")
      .eq("user_id", userId)
      .in("workout_type", family)
      .gte("workout_date", lookbackStart)
      .lte("workout_date", lookbackEnd)
      .gte("workout_distance_miles", minDist)
      .lte("workout_distance_miles", maxDist)
      .order("workout_date", { ascending: false })
      .limit(20);

    if (error) {
      console.warn("findSimilarPriorWorkout: query error", error.message);
      return null;
    }

    type Row = {
      workout_date: string;
      workout_type: string;
      workout_distance_miles: number;
      workout_pace_per_mile: string | null;
      workout_duration_minutes: number | null;
    };

    const candidates = (data ?? []) as Row[];
    if (candidates.length === 0) return null;

    // Score each candidate. Smaller distance delta = better. Recency is
    // tiebreak — closer in time wins when distance match is similar.
    let best: { row: Row; score: number; daysAgo: number } | null = null;
    for (const row of candidates) {
      const paceSec = parsePace(row.workout_pace_per_mile)
        ?? deriveAveragePace(row.workout_distance_miles, row.workout_duration_minutes);
      if (paceSec == null) continue;

      const distDelta = Math.abs(row.workout_distance_miles - current.distanceMiles) / current.distanceMiles;
      const daysAgo = Math.round(
        (currentDate.getTime() - new Date(row.workout_date).getTime()) / 86400000,
      );
      // Lower score = better. Distance delta dominates; recency adds a
      // small penalty (0.001 per day) so 21-days-ago beats 70-days-ago
      // when distance match is identical.
      const score = distDelta + daysAgo * 0.001;
      if (!best || score < best.score) {
        best = { row, score, daysAgo };
      }
    }

    if (!best) return null;
    const finalPaceSec = parsePace(best.row.workout_pace_per_mile)
      ?? deriveAveragePace(best.row.workout_distance_miles, best.row.workout_duration_minutes);
    if (finalPaceSec == null) return null;

    return {
      date: best.row.workout_date,
      daysAgo: best.daysAgo,
      workoutType: best.row.workout_type,
      distanceMiles: best.row.workout_distance_miles,
      paceSecPerMile: finalPaceSec,
    };
  } catch (err) {
    console.warn("findSimilarPriorWorkout: error", err);
    return null;
  }
}

export interface ProgressionComparison {
  block: string;
  /** True when today is meaningfully better (longer or faster, or both). */
  hasImprovement: boolean;
  /** True when today is meaningfully worse (shorter or slower). */
  hasRegression: boolean;
}

/**
 * Workout types that are quality sessions by intent — the comparison is
 * always worth surfacing for these, even when the delta is small. A 6mi
 * tempo @ 5:25 vs 6.5mi tempo @ 5:24 is still a coachable session, not
 * noise. The athlete put quality work in; the coach should read it.
 */
const FAST_WORKOUT_TYPES = new Set([
  "tempo",
  "progression",
  "threshold",
  "intervals",
  "interval",
  "race",
]);

/**
 * Distance threshold above which a run is a "long effort" — comparison
 * always surfaces regardless of delta size. Long runs accumulate
 * meaningful aerobic signal; small differences in distance or pace at
 * 14+ mi are still worth noting.
 */
const LONG_EFFORT_DISTANCE_MI = 12;

/**
 * Format the progression block for the LLM.
 *
 * Always evaluates when:
 *   - Workout is a quality session (tempo / threshold / intervals / race)
 *   - Distance exceeds the long-effort threshold (>12 mi)
 *
 * Otherwise applies a noise filter — easy/recovery/moderate runs under
 * the long-effort threshold need a meaningful delta (≥10% distance or
 * ≥2% pace) before the block fires. Two 5mi easy runs at 8:30 vs 8:32
 * isn't a coaching moment.
 *
 * Returns null only when the block is filtered as noise, never for
 * quality sessions or long efforts.
 */
export function formatProgressionBlock(
  current: CurrentWorkout,
  prior: PriorWorkout,
): ProgressionComparison | null {
  const distDeltaMi = current.distanceMiles - prior.distanceMiles;
  const distDeltaPct = (distDeltaMi / prior.distanceMiles) * 100;
  const paceDeltaSec = current.paceSecPerMile - prior.paceSecPerMile;
  const paceDeltaPct = (paceDeltaSec / prior.paceSecPerMile) * 100;

  // Always-evaluate cases: quality sessions and long efforts.
  const isFastEffort = FAST_WORKOUT_TYPES.has(current.workoutType.toLowerCase());
  const isLongEffort = current.distanceMiles > LONG_EFFORT_DISTANCE_MI;
  const alwaysEvaluate = isFastEffort || isLongEffort;

  // Noise filter only applies to non-quality, non-long runs.
  if (!alwaysEvaluate) {
    const distMeaningful = Math.abs(distDeltaPct) >= 10;
    const paceMeaningful = Math.abs(paceDeltaPct) >= 2;
    if (!distMeaningful && !paceMeaningful) return null;
  }

  const distLine = distDeltaMi > 0
    ? `+${distDeltaMi.toFixed(1)} mi (+${distDeltaPct.toFixed(0)}% distance)`
    : `${distDeltaMi.toFixed(1)} mi (${distDeltaPct.toFixed(0)}% distance)`;
  // Pace: faster pace = fewer seconds = negative delta = "faster"
  const paceLine = paceDeltaSec < 0
    ? `${paceDeltaSec} sec/mi (${Math.abs(paceDeltaPct).toFixed(1)}% faster)`
    : `+${paceDeltaSec} sec/mi (${paceDeltaPct.toFixed(1)}% slower)`;

  const weeksAgo = Math.round(prior.daysAgo / 7);
  const whenLabel = weeksAgo <= 1 ? `${prior.daysAgo} days ago` : `${weeksAgo} weeks ago`;

  const lines = [
    `## Workout progression`,
    `Today: ${current.distanceMiles.toFixed(1)} mi ${current.workoutType} @ ${formatPace(current.paceSecPerMile)}/mi`,
    `Most similar prior ${prior.workoutType} (${whenLabel}, ${prior.date}): ${prior.distanceMiles.toFixed(1)} mi @ ${formatPace(prior.paceSecPerMile)}/mi`,
    `Delta: ${distLine}, ${paceLine}`,
  ];

  // When the block fires for a quality/long session but the deltas are
  // tiny, give the LLM a cue so it doesn't over-claim "real progression."
  // Threshold for "essentially equivalent": <5% distance AND <1% pace.
  const isEssentiallyEquivalent =
    Math.abs(distDeltaPct) < 5 && Math.abs(paceDeltaPct) < 1;
  if (alwaysEvaluate && isEssentiallyEquivalent) {
    const reason = isFastEffort && isLongEffort
      ? "quality session and long effort"
      : isFastEffort
        ? "quality session"
        : "long effort";
    lines.push(
      `Note: essentially equivalent to the prior ${prior.workoutType} — surfaced because ${reason} sessions always warrant a read, but don't frame this as "real progression."`,
    );
  }

  // Improvement: longer OR faster (or both). Regression: shorter OR slower.
  // The "or" cases get nuanced commentary from the LLM.
  const hasImprovement = (distDeltaPct >= 10) || (paceDeltaSec <= -3);
  const hasRegression = (distDeltaPct <= -10) || (paceDeltaSec >= 3);

  return {
    block: lines.join("\n"),
    hasImprovement,
    hasRegression,
  };
}

// Helper used by both the matcher and other internals.
function deriveAveragePace(distMi: number | null, durMin: number | null): number | null {
  if (!distMi || !durMin || distMi <= 0 || durMin <= 0) return null;
  return Math.round((Number(durMin) * 60) / Number(distMi));
}

// ── Workout splits — rep-by-rep + pattern detection ──────

/**
 * A single segment of a workout — from Garmin/HealthKit (pace_segments)
 * or extracted from voice memo (extracted_data.intervals).
 */
export interface WorkoutSplit {
  /** Free-text label: "Rep 1", "Warmup", "800m #3", etc. */
  label: string;
  distanceMiles: number;
  paceSecPerMile: number;
  /** Optional. From watch data. */
  avgHeartRate?: number;
  /** "warmup" / "cooldown" / "work" / unknown. Used for pattern detection. */
  effortKind: "warmup" | "cooldown" | "work" | "unknown";
}

const WARMUP_LABELS = new Set(["warmup", "warm-up", "warm up", "wu"]);
const COOLDOWN_LABELS = new Set(["cooldown", "cool-down", "cool down", "cd"]);

function classifyEffortKind(rawEffort: string | undefined | null): WorkoutSplit["effortKind"] {
  if (!rawEffort) return "unknown";
  const e = rawEffort.toLowerCase().trim();
  if (WARMUP_LABELS.has(e)) return "warmup";
  if (COOLDOWN_LABELS.has(e)) return "cooldown";
  // Anything else (interval, tempo, race_pace, threshold, hard, etc.) is "work".
  return "work";
}

/**
 * Normalize Garmin/HealthKit `pace_segments` rows into WorkoutSplit shape.
 */
export function splitsFromPaceSegments(
  segments: Array<{
    effort?: string;
    distance_miles?: number | string;
    pace_per_mile?: string;
    avg_heart_rate?: number;
  }> | null | undefined,
): WorkoutSplit[] {
  if (!Array.isArray(segments) || segments.length === 0) return [];
  const out: WorkoutSplit[] = [];
  let workIndex = 0;
  for (const seg of segments) {
    const dist = typeof seg.distance_miles === "number"
      ? seg.distance_miles
      : parseFloat(String(seg.distance_miles ?? "0"));
    const paceSec = parsePace(seg.pace_per_mile ?? "");
    if (!dist || dist <= 0 || paceSec == null) continue;
    const effortKind = classifyEffortKind(seg.effort);
    const label = (() => {
      if (effortKind === "warmup") return "Warmup";
      if (effortKind === "cooldown") return "Cooldown";
      if (effortKind === "work") {
        workIndex++;
        return `Rep ${workIndex}`;
      }
      return seg.effort ?? "Segment";
    })();
    out.push({
      label,
      distanceMiles: dist,
      paceSecPerMile: paceSec,
      avgHeartRate: seg.avg_heart_rate,
      effortKind,
    });
  }
  return out;
}

/**
 * Normalize voice-memo-extracted `intervals` into WorkoutSplit shape.
 * The voice path stores them as `{distance: "800m", time: "2:50", count: 4}`
 * — we expand the count into N rep entries.
 */
export function splitsFromExtractedIntervals(
  intervals: Array<{
    distance?: string;
    time?: string;
    rest?: string;
    count?: number;
  }> | null | undefined,
): WorkoutSplit[] {
  if (!Array.isArray(intervals) || intervals.length === 0) return [];
  const out: WorkoutSplit[] = [];
  let repIdx = 0;
  for (const iv of intervals) {
    const distMi = parseDistanceToMiles(iv.distance);
    const timeSec = parseTimeToSeconds(iv.time);
    if (!distMi || !timeSec) continue;
    const paceSec = Math.round(timeSec / distMi);
    const count = Math.max(1, iv.count ?? 1);
    for (let i = 0; i < count; i++) {
      repIdx++;
      out.push({
        label: `Rep ${repIdx}`,
        distanceMiles: distMi,
        paceSecPerMile: paceSec,
        effortKind: "work",
      });
    }
  }
  return out;
}

/**
 * Format the splits block for the LLM. Returns null when there's nothing
 * useful — fewer than 2 work segments, or no segments at all.
 *
 * Each segment is shown with its zone classification (deterministic).
 * A pattern line summarizes the shape — consistent / fading / negative
 * split — based on the work segments only (warmup/cooldown excluded).
 */
export function formatSplitsBlock(
  splits: WorkoutSplit[],
  zones: PaceZones | null,
): string {
  if (splits.length === 0) return "";
  const work = splits.filter((s) => s.effortKind === "work" || s.effortKind === "unknown");
  if (work.length < 2) return "";

  const lines: string[] = ["## Workout splits"];
  for (const s of splits) {
    const zoneNote = zones
      ? ` (${classifyPace(s.paceSecPerMile, zones).bucket})`
      : "";
    const hrNote = s.avgHeartRate ? ` · ${s.avgHeartRate} bpm` : "";
    lines.push(
      `- ${s.label}: ${s.distanceMiles.toFixed(2)} mi @ ${formatPace(s.paceSecPerMile)}/mi${zoneNote}${hrNote}`,
    );
  }

  // Pattern detection — compare first half vs second half of work reps.
  const pattern = detectSplitPattern(work);
  if (pattern) lines.push(`Pattern: ${pattern}`);

  return lines.join("\n");
}

function detectSplitPattern(work: WorkoutSplit[]): string | null {
  if (work.length < 2) return null;

  const mid = Math.floor(work.length / 2);
  const firstHalf = work.slice(0, mid);
  const secondHalf = work.slice(mid);
  if (firstHalf.length === 0 || secondHalf.length === 0) return null;

  const avg = (xs: WorkoutSplit[]) =>
    xs.reduce((sum, s) => sum + s.paceSecPerMile, 0) / xs.length;
  const firstAvg = avg(firstHalf);
  const secondAvg = avg(secondHalf);
  const delta = Math.round(secondAvg - firstAvg);

  // Range of paces across all work segments — flag drift/spread.
  const paces = work.map((s) => s.paceSecPerMile);
  const spread = Math.max(...paces) - Math.min(...paces);

  if (Math.abs(delta) <= 3 && spread <= 8) {
    return `Consistent — work reps held within ${spread} sec/mi.`;
  }
  if (delta >= 4) {
    return `Fade — second half averaged ${delta} sec/mi slower than the first.`;
  }
  if (delta <= -4) {
    return `Negative split — second half averaged ${Math.abs(delta)} sec/mi faster than the first.`;
  }
  if (spread > 8) {
    return `Mixed — ${spread} sec/mi spread across reps without a clear fade/build pattern.`;
  }
  return null;
}

// ── Distance / time parsers for voice-extracted intervals ────

function parseDistanceToMiles(s: string | undefined): number | null {
  if (!s) return null;
  const txt = s.toLowerCase().trim();

  // Direct mile values: "1mi", "1 mile", "0.5 mile"
  const mileMatch = txt.match(/^(\d+(?:\.\d+)?)\s*(?:mi|mile|miles)?$/);
  if (mileMatch && (txt.includes("mi") || txt.includes("mile"))) {
    return parseFloat(mileMatch[1]);
  }

  // Meter values: "800m", "1200m", "400 m"
  const meterMatch = txt.match(/^(\d+)\s*m$/);
  if (meterMatch) {
    return parseInt(meterMatch[1]) / 1609.344;
  }

  // Kilometer values: "1k", "2km", "5 km"
  const kmMatch = txt.match(/^(\d+(?:\.\d+)?)\s*k(?:m)?$/);
  if (kmMatch) {
    return parseFloat(kmMatch[1]) * 1000 / 1609.344;
  }

  // Bare number — assume miles (matches the iOS convention).
  const bareMatch = txt.match(/^(\d+(?:\.\d+)?)$/);
  if (bareMatch) return parseFloat(bareMatch[1]);

  return null;
}

function parseTimeToSeconds(s: string | undefined): number | null {
  if (!s) return null;
  const txt = s.trim();
  // H:MM:SS
  const hms = txt.match(/^(\d+):(\d{1,2}):(\d{1,2})$/);
  if (hms) {
    return parseInt(hms[1]) * 3600 + parseInt(hms[2]) * 60 + parseInt(hms[3]);
  }
  // MM:SS or M:SS
  const ms = txt.match(/^(\d+):(\d{1,2})$/);
  if (ms) {
    return parseInt(ms[1]) * 60 + parseInt(ms[2]);
  }
  // Bare seconds
  const bare = txt.match(/^(\d+)$/);
  if (bare) return parseInt(bare[1]);
  return null;
}

// ── Internals ────────────────────────────────────────────

async function safeLoadZones(
  supabase: SupabaseClient,
  userId: string,
): Promise<PaceZones | null> {
  try {
    return await fetchAndComputePaceZones(supabase, userId);
  } catch (err) {
    console.warn("coach-context: zones load failed:", err);
    return null;
  }
}

async function safeLoadGoal(
  supabase: SupabaseClient,
  userId: string,
): Promise<GoalContext | null> {
  try {
    const { data } = await supabase
      .from("training_plans")
      .select("target_race_distance, target_time_seconds, end_date")
      .eq("user_id", userId)
      .eq("status", "active")
      .order("start_date", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (!data?.target_race_distance || !data?.target_time_seconds) return null;

    // training_plans.end_date is the race day for race-prep plans.
    const raceDate = (data.end_date as string | null) ?? null;
    const weeksToRace = raceDate
      ? Math.max(0, Math.round((new Date(raceDate).getTime() - Date.now()) / (7 * 86400 * 1000)))
      : null;

    return {
      raceDistance: data.target_race_distance as string,
      targetTimeSeconds: data.target_time_seconds as number,
      raceDate,
      weeksToRace,
    };
  } catch (err) {
    console.warn("coach-context: goal load failed:", err);
    return null;
  }
}

function rangeResult(
  P: number,
  bucket: PaceClassification["bucket"],
  label: string,
  range: PaceRange,
): PaceClassification {
  return {
    paceSecsPerMile: P,
    bucket,
    summary: `Executed ${formatPace(P)}/mi — in the ${label} band (${formatPace(range.paceFast)}-${formatPace(range.paceSlow)}/mi).`,
  };
}

interface PrescribedStep {
  label: string;
  paceSec: number;
  distanceMiles?: number;
  effort?: string;
}

interface MatchedStep {
  label: string;
  prescribedSec: number;
  executedSec: number;
}

function parseSteps(workoutData: Record<string, unknown>): PrescribedStep[] {
  const steps: PrescribedStep[] = [];
  const stepsRaw = (workoutData.steps as unknown) ?? (workoutData.intervals as unknown);
  if (!Array.isArray(stepsRaw)) return steps;

  for (const s of stepsRaw) {
    if (!s || typeof s !== "object") continue;
    const obj = s as Record<string, unknown>;
    const targetPace = obj.target_pace ?? obj.targetPace ?? obj.pace;
    if (typeof targetPace !== "string") continue;
    const sec = parsePace(targetPace);
    if (sec == null) continue;
    steps.push({
      label: (obj.label ?? obj.name ?? obj.effort ?? "Step") as string,
      paceSec: sec,
      distanceMiles: typeof obj.distance_miles === "number" ? obj.distance_miles : undefined,
      effort: typeof obj.effort === "string" ? obj.effort : undefined,
    });
  }
  return steps;
}

function matchStepsToSegments(
  steps: PrescribedStep[],
  segments: NonNullable<ExecutedSummary["paceSegments"]>,
): MatchedStep[] {
  // Simple positional match — first step ↔ first segment, etc.
  // Skips warmup/cooldown segments by effort label when present.
  const filteredSegs = segments.filter((s) => {
    const e = (s.effort ?? "").toLowerCase();
    return !["warmup", "warm-up", "warm up", "cooldown", "cool-down", "cool down"].includes(e);
  });

  const out: MatchedStep[] = [];
  const n = Math.min(steps.length, filteredSegs.length);
  for (let i = 0; i < n; i++) {
    const exec = filteredSegs[i].pace_per_mile ? parsePace(filteredSegs[i].pace_per_mile!) : null;
    if (exec == null) continue;
    out.push({
      label: steps[i].label,
      prescribedSec: steps[i].paceSec,
      executedSec: exec,
    });
  }
  return out;
}

interface ExpectedBand {
  label: string;
  summary: string;
  paceFast: number;
  paceSlow: number;
}

function expectedBandForType(type: string, zones: PaceZones | null): ExpectedBand | null {
  if (!zones) return null;
  const t = type.toLowerCase();
  if ((t === "easy" || t === "recovery") && zones.easy) {
    return { label: "easy band", summary: bandSummary(zones.easy), paceFast: zones.easy.paceFast, paceSlow: zones.easy.paceSlow };
  }
  if (t === "long_run" && zones.easy) {
    return { label: "long-run band (= easy)", summary: bandSummary(zones.easy), paceFast: zones.easy.paceFast, paceSlow: zones.easy.paceSlow };
  }
  if ((t === "tempo" || t === "threshold") && zones.halfMarathon) {
    return { label: "around HMP", summary: `${formatPace(zones.halfMarathon.pace)}/mi ± 10`, paceFast: zones.halfMarathon.pace - 10, paceSlow: zones.halfMarathon.pace + 10 };
  }
  if ((t === "interval" || t === "intervals") && zones.tenK && zones.fiveK) {
    return { label: "10K-5K range", summary: `${formatPace(zones.fiveK.pace)}-${formatPace(zones.tenK.pace)}/mi`, paceFast: zones.fiveK.pace, paceSlow: zones.tenK.pace };
  }
  if (t === "race" && zones.marathon) {
    return { label: "race pace (varies by distance)", summary: "see goal", paceFast: zones.fiveK?.pace ?? 0, paceSlow: zones.marathon.pace };
  }
  return null;
}

function bandSummary(range: PaceRange): string {
  return `${formatPace(range.paceFast)}-${formatPace(range.paceSlow)}/mi`;
}

interface RangeDeviation {
  outside: boolean;
  note: string;
}

function describeRangeDeviation(paceSec: number, band: ExpectedBand): RangeDeviation {
  if (paceSec < band.paceFast) {
    const delta = band.paceFast - paceSec;
    return {
      outside: true,
      note: `Ran ${delta}s/mi faster than the band's fast bound. ${delta > 20 ? "Significantly hotter than prescribed." : "Edge of the band — fine occasionally, watch the cumulative cost."}`,
    };
  }
  if (paceSec > band.paceSlow) {
    const delta = paceSec - band.paceSlow;
    return {
      outside: true,
      note: `Ran ${delta}s/mi slower than the band's slow bound. ${delta > 30 ? "Notably easier than prescribed." : "Slightly soft — could be intentional recovery."}`,
    };
  }
  return { outside: false, note: "" };
}

// ── Formatters ───────────────────────────────────────────

function formatPace(sec: number): string {
  const total = Math.max(0, Math.round(sec));
  return `${Math.floor(total / 60)}:${(total % 60).toString().padStart(2, "0")}`;
}

function formatHms(sec: number): string {
  const total = Math.max(0, Math.round(sec));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  if (h > 0) return `${h}:${m.toString().padStart(2, "0")}:${s.toString().padStart(2, "0")}`;
  return `${m}:${s.toString().padStart(2, "0")}`;
}

function parsePace(s: string): number | null {
  const m = s.match(/^(\d{1,2}):(\d{2})$/);
  if (!m) return null;
  const min = parseInt(m[1]);
  const sec = parseInt(m[2]);
  if (isNaN(min) || isNaN(sec)) return null;
  return min * 60 + sec;
}

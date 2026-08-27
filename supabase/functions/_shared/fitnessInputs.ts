// ============================================================================
// fitnessInputs.ts — assemble a PredictionInput from the database.
//
// WHY THIS EXISTS (2026-08-24). The assembly lived inside
// `compute-fitness-snapshot/index.ts`, which meant the only way to run the
// predictor over history was to re-implement the fetch somewhere else. A
// backtest whose inputs are assembled differently from production is not
// measuring the shipped model — it is measuring a sibling of it, and every
// disagreement becomes an argument about the harness instead of the model.
// So: one builder, two callers.
//
//   production  buildPredictionInput(db, userId, now)
//               → every default on, identical to the pre-extraction behavior.
//
//   replay      buildPredictionInput(db, userId, D, { asOf: D, ... })
//               → the same code, restricted to rows that existed at D.
//
// POINT-IN-TIME IS NOT FREE, AND THE LIMITS ARE NAMED HERE RATHER THAN
// DISCOVERED LATER. Three classes of input:
//
//   1. ROWS WITH `created_at` — training_logs, running_workout_laps,
//      fitness_snapshots, training_plans. Genuinely reconstructible; `asOf`
//      filters them. Verified 2026-08-24: created_at is present on 307/307
//      training_logs and never precedes workout_date. It is also NECESSARY —
//      median ingest lag is 0.36d but the mean is 9.4d and 106 of 307 rows
//      landed more than two days after the workout (the tail is the two-year
//      HealthKit backfill, max 708d). Filtering on `workout_date` instead
//      would leak the future on a third of the table.
//
//   2. COLUMNS WRITTEN LATER ONTO AN EXISTING ROW — `parsed_structure`,
//      `weather_actual`, `pace_segments`, `race_result`. A row's `created_at`
//      gates when the ROW appeared, not when each COLUMN was filled. There is
//      no per-column history, and `workout_parse_jobs` deletes on success, so
//      the parse instant is unrecoverable for historical rows. We accept the
//      row's `created_at` as the proxy and say so: parse fires inline from
//      strava-sync (`fireParseStructure`) within minutes of ingest, and
//      backfilled rows were parsed as part of the same backfill, so the proxy
//      is close for both populations. It is nonetheless OPTIMISTIC — a replay
//      may see structure a few minutes-to-hours before the live model did.
//      Never treat a sub-1% replay difference as signal.
//
//   3. MUTABLE SINGLETONS WITH NO HISTORY — `athlete_state.fitness_signal`.
//      There is no `created_at` on that table and no snapshot of prior values.
//      Its value at date D is UNKNOWABLE. Reading today's value into a replay
//      of March would leak eleven weeks of future EF evidence into the gate,
//      so replay defaults `includeEfficiencySignal: false`, which is exactly
//      the documented no-evidence path (gate inert, age-scaled cap). This is
//      a real coverage hole in the backtest, not a rounding error: the EF
//      gate cannot be scored until the signal is versioned.
//
// Extracted verbatim — no behavior change. Anything that looks like a bug
// below was a bug before the move and is preserved deliberately; fixing it
// here would silently change production while claiming to be a refactor.
// ============================================================================

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  paceStringToSeconds,
  type DetectedRace,
  type EfficiencyBucketInput,
  type LapInput,
  type PredictionInput,
  type PriorSnapshotInput,
  type RaceType,
  type VoiceLogInput,
  type WorkoutInput,
} from "./fitnessPrediction.ts";

/**
 * Distance table used to seed race paces.
 *
 * NOTE (preserved, not fixed): these are rounded to 3dp while
 * `fitnessPrediction.RACE_TYPE_MILES` carries 5 (6.21371 vs 6.214). Only
 * `seededRaces[].paceSecondsPerMile` is derived from it, and the model
 * recomputes pace from `totalTimeSeconds` with its own table before anchoring,
 * so the difference reaches nothing but `dedupeRaces`' 2% tolerance. Left
 * alone so this extraction changes no output.
 */
export const RACE_TYPE_MILES: Record<RaceType, number> = {
  mile: 1.0,
  fiveK: 3.107,
  tenK: 6.214,
  half: 13.109,
  marathon: 26.219,
};

export interface BuildInputOpts {
  /** Replay only: exclude rows created at or after this instant. */
  asOf?: Date | null;
  /**
   * Replay supplies its OWN chain of predictions here. The curve is
   * path-dependent (`smoothFitnessPace`), so a replay that reads the stored
   * snapshots is scoring a mixture of the model and its own history rather
   * than the model. `undefined` = fetch from the database (production).
   */
  priorSnapshots?: PriorSnapshotInput[];
  /** See class 3 above. Default true (production); replay passes false. */
  includeEfficiencySignal?: boolean;
}

export interface BuiltPredictionInput {
  input: PredictionInput;
  /** The raw rows, needed by the caller's race-candidate tagging pass. */
  logRows: Array<Record<string, unknown>>;
  /** What the point-in-time restriction actually excluded, for the record. */
  provenance: {
    asOf: string | null;
    logRowCount: number;
    lapRowCount: number;
    priorSnapshotCount: number;
    efficiencySignalUsed: boolean;
  };
}

export async function buildPredictionInput(
  db: SupabaseClient,
  userId: string,
  now: Date,
  opts: BuildInputOpts = {},
): Promise<BuiltPredictionInput> {
  const asOf = opts.asOf ?? null;
  const asOfIso = asOf ? asOf.toISOString() : null;
  const includeEf = opts.includeEfficiencySignal ?? true;

  const cutoff30 = new Date(now.getTime() - 30 * 86400000).toISOString().slice(0, 10);
  const cutoff180 = new Date(now.getTime() - 180 * 86400000).toISOString().slice(0, 10);
  const cutoff112 = new Date(now.getTime() - 112 * 86400000).toISOString();
  const cutoff21 = new Date(now.getTime() - 21 * 86400000).toISOString();

  // Training logs: last 180d (covers race detection); the 30d window is derived
  // by date below. One row can be both a run and carry notes/parse/segments.
  let logQ = db
    .from("training_logs")
    .select(
      "id, workout_date, workout_distance_miles, workout_duration_minutes, workout_pace_per_mile, workout_type, cleaned_notes, notes, workout_notes, parsed_structure, pace_segments, race_result, weather_actual",
    )
    .eq("user_id", userId)
    .gte("workout_date", cutoff180);
  if (asOfIso) logQ = logQ.lt("created_at", asOfIso);
  const { data: logRows, error: logErr } = await logQ
    .order("workout_date", { ascending: false })
    .limit(2000);
  if (logErr) throw new Error(`training_logs: ${logErr.message}`);

  const extendedWorkouts: WorkoutInput[] = [];
  const extendedVoiceLogs: VoiceLogInput[] = [];
  const seededRaces: DetectedRace[] = [];
  const workoutDateById = new Map<string, string>();
  for (const row of logRows ?? []) {
    const date = toDay(row.workout_date as string);
    if (!date) continue;
    if (row.id) workoutDateById.set(String(row.id), date);

    const miles = num(row.workout_distance_miles);
    const durationMinutes = num(row.workout_duration_minutes);
    // workout_pace_per_mile is stored as an "M:SS" text string, not seconds.
    // Fall back to duration/distance when the text is missing or malformed.
    let paceSec = paceStringToSeconds(String(row.workout_pace_per_mile ?? ""));
    if (paceSec <= 0 && miles > 0 && durationMinutes > 0) paceSec = (durationMinutes * 60) / miles;
    if (miles > 0 && paceSec > 0) {
      extendedWorkouts.push({
        date,
        distanceMiles: miles,
        durationMinutes,
        paceSecondsPerMile: paceSec,
        type: (row.workout_type as string) ?? undefined,
      });
    }

    const notes = [row.cleaned_notes, row.notes, row.workout_notes].filter(Boolean).join(" ").trim();
    extendedVoiceLogs.push({
      date,
      notes,
      pacesMentioned: [],
      paceSegments: mapPaceSegments(row.pace_segments),
      parsedStructure: mapParsedStructure(row.parsed_structure),
      weather: mapWeather(row.weather_actual),
    });
  }

  const workouts = extendedWorkouts.filter((w) => w.date >= cutoff30);
  const voiceLogs = extendedVoiceLogs.filter((v) => v.date >= cutoff30);

  // Lap-level interval data (last 21 days) — the rest-aware, heat-stamped,
  // per-rep signal the v2 model merges into its hard-effort pool.
  let lapQ = db
    .from("running_workout_laps")
    .select(
      "workout_id, lap_index, distance_meters, moving_time_seconds, avg_pace_sec_per_mile, is_rest, total_elevation_gain, temp_f, dew_point_f, heat_adjusted_pace_sec_per_mile, lap_start_at",
    )
    .eq("user_id", userId)
    .gte("lap_start_at", cutoff21);
  if (asOfIso) lapQ = lapQ.lt("created_at", asOfIso);
  const { data: lapRows } = await lapQ.order("lap_start_at", { ascending: true }).limit(2000);

  // Confirmed races — ALL TIME (2026-07-17). Races live in training_logs
  // (workout_type='race' + race_result), not a separate table. Recent ones
  // (≤36 wk) anchor current fitness; older ones are lifetime PRs: they feed
  // speed evidence and the PR display, never the current-fitness anchor.
  let raceQ = db
    .from("training_logs")
    .select("id, workout_date, race_result")
    .eq("user_id", userId)
    .not("race_result", "is", null);
  if (asOfIso) raceQ = raceQ.lt("created_at", asOfIso);
  const { data: raceRows } = await raceQ.order("workout_date", { ascending: false }).limit(100);
  for (const row of raceRows ?? []) {
    const date = toDay(row.workout_date as string);
    if (!date) continue;
    if (row.id) workoutDateById.set(String(row.id), date);
    const rr = row.race_result as { distance?: string; finish_time_seconds?: number } | null;
    if (rr && typeof rr.finish_time_seconds === "number") {
      const rt = distanceToRaceType(String(rr.distance ?? ""));
      if (rt) {
        seededRaces.push({
          raceType: rt,
          paceSecondsPerMile: rr.finish_time_seconds / RACE_TYPE_MILES[rt],
          date,
          totalTimeSeconds: rr.finish_time_seconds,
          // Lets the model find this race's laps for grade+heat adjustment
          // (race performances read as flat-cool equivalents, 2026-07-17).
          sourceWorkoutId: String(row.id),
        });
      }
    }
  }

  // Race-day laps (2026-07-17): confirmed races can be months older than the
  // 21-day training window, but their laps carry the hills + weather needed to
  // read the performance as a flat-cool equivalent. Fetch them separately.
  const raceWorkoutIds = seededRaces
    .map((r) => r.sourceWorkoutId)
    .filter((id): id is string => typeof id === "string" && id.length > 0);
  let raceLapRows: typeof lapRows = [];
  if (raceWorkoutIds.length > 0) {
    let rlQ = db
      .from("running_workout_laps")
      .select(
        "workout_id, lap_index, distance_meters, moving_time_seconds, avg_pace_sec_per_mile, is_rest, total_elevation_gain, temp_f, dew_point_f, heat_adjusted_pace_sec_per_mile, lap_start_at",
      )
      .eq("user_id", userId)
      .in("workout_id", raceWorkoutIds);
    if (asOfIso) rlQ = rlQ.lt("created_at", asOfIso);
    const { data } = await rlQ.order("lap_start_at", { ascending: true }).limit(500);
    raceLapRows = data ?? [];
  }

  const laps: LapInput[] = [];
  const seenLapKeys = new Set<string>();
  for (const l of [...(lapRows ?? []), ...(raceLapRows ?? [])]) {
    const key = `${l.workout_id}#${l.lap_index}`;
    if (seenLapKeys.has(key)) continue;
    seenLapKeys.add(key);
    const date = workoutDateById.get(String(l.workout_id)) ?? toDay(String(l.lap_start_at ?? ""));
    if (!date) continue;
    laps.push({
      workoutId: String(l.workout_id),
      date,
      lapIndex: num(l.lap_index),
      distanceMeters: numOrNull(l.distance_meters),
      movingTimeSeconds: numOrNull(l.moving_time_seconds),
      avgPaceSecPerMile: numOrNull(l.avg_pace_sec_per_mile),
      isRest: typeof l.is_rest === "boolean" ? l.is_rest : null,
      totalElevationGain: numOrNull(l.total_elevation_gain),
      tempF: numOrNull(l.temp_f),
      dewPointF: numOrNull(l.dew_point_f),
      heatAdjustedPaceSecPerMile: numOrNull(l.heat_adjusted_pace_sec_per_mile),
    });
  }

  // Prior snapshots (last 16 weeks) for the decay-gated baseline fallback AND
  // the curve's prior. `data_source` is required, not decorative: the curve
  // damps only against rows this model wrote (see fitnessCurve.isOwnSnapshot).
  let priorSnapshots: PriorSnapshotInput[];
  if (opts.priorSnapshots !== undefined) {
    priorSnapshots = opts.priorSnapshots;
  } else {
    let snapQ = db
      .from("fitness_snapshots")
      .select("created_at, estimated_10k_pace_seconds, confidence, data_source")
      .eq("user_id", userId)
      .gte("created_at", cutoff112);
    if (asOfIso) snapQ = snapQ.lt("created_at", asOfIso);
    const { data: snapRows } = await snapQ.order("created_at", { ascending: false }).limit(50);
    priorSnapshots = (snapRows ?? []).map((s) => ({
      createdAt: s.created_at as string,
      estimated10kPaceSeconds: num(s.estimated_10k_pace_seconds),
      confidence: (s.confidence as string) ?? "Low",
      dataSource: (s.data_source as string | null) ?? null,
    }));
  }

  // Active training plan goal (optional Medium anchor).
  let planQ = db
    .from("training_plans")
    .select("target_race_distance, target_time_seconds, status")
    .eq("user_id", userId)
    .eq("status", "active");
  if (asOfIso) planQ = planQ.lt("created_at", asOfIso);
  const { data: planRow } = await planQ.maybeSingle();
  let plan: PredictionInput["plan"] = null;
  if (planRow && num(planRow.target_time_seconds) > 0) {
    const rt = distanceToRaceType(String(planRow.target_race_distance ?? ""));
    if (rt) {
      plan = {
        status: "active",
        raceDistanceKey: rt,
        targetTimeSeconds: num(planRow.target_time_seconds),
        raceDistanceMiles: RACE_TYPE_MILES[rt],
      };
    }
  }

  // EF buckets from the athlete-state fitness signal (heat-aware speed-per-
  // beat, 84d window). Corroborates the training signal's slow direction —
  // see the EF gate in fitnessPrediction. Nightly ordering makes this read a
  // day stale (snapshot 03:30, rebuild 04:00); immaterial for an 11-week
  // trend. Missing row / null signal degrades to pre-gate behavior.
  //
  // Replay passes includeEf=false — see class 3 in the header.
  let efficiencySignal: EfficiencyBucketInput[] | null = null;
  // experience_level rides along on the same row — unlike fitness_signal it is
  // effectively static (an athlete's training age doesn't reset), so reading
  // today's value into a replay of the past carries none of EF's class-3 risk.
  // Fetched regardless of `includeEf`.
  let experienceLevel: string | null = null;
  {
    const { data: stateRow } = await db
      .from("athlete_state")
      .select("fitness_signal, experience_level")
      .eq("user_id", userId)
      .maybeSingle();
    experienceLevel = (stateRow?.experience_level as string | null) ?? null;
    if (includeEf) {
      const rawEff = (stateRow?.fitness_signal as { efficiency?: Array<Record<string, unknown>> } | null)
        ?.efficiency;
      efficiencySignal = Array.isArray(rawEff)
        ? rawEff.map((b) => ({
          bucket: String(b.bucket ?? ""),
          direction: String(b.direction ?? ""),
          confidence: String(b.confidence ?? ""),
          efDeltaPct: numOrNull(b.ef_delta_pct),
          recentSamples: num(b.recent_samples),
          baselineSamples: num(b.baseline_samples),
        }))
        : null;
    }
  }

  return {
    input: {
      workouts,
      voiceLogs,
      extendedWorkouts,
      extendedVoiceLogs,
      priorSnapshots,
      plan,
      seededRaces,
      laps,
      efficiencySignal,
      experienceLevel,
      now,
    },
    logRows: (logRows ?? []) as Array<Record<string, unknown>>,
    provenance: {
      asOf: asOfIso,
      logRowCount: (logRows ?? []).length,
      lapRowCount: laps.length,
      priorSnapshotCount: priorSnapshots.length,
      efficiencySignalUsed: includeEf && efficiencySignal !== null,
    },
  };
}

// ---------------------------------------------------------------------------
// Mapping helpers (snake_case DB → module camelCase inputs).
// ---------------------------------------------------------------------------

export function distanceToRaceType(raw: string): RaceType | null {
  switch (raw.toLowerCase().trim()) {
    case "mile":
    case "1mi":
    case "1_mile":
      return "mile";
    case "5k":
    case "fivek":
      return "fiveK";
    case "10k":
    case "tenk":
      return "tenK";
    case "half":
    case "half_marathon":
    case "half-marathon":
    case "halfmarathon":
    case "hm":
      return "half";
    case "marathon":
    case "full":
      return "marathon";
    default:
      return null;
  }
}

// deno-lint-ignore no-explicit-any
export function mapPaceSegments(raw: any): VoiceLogInput["paceSegments"] {
  if (!Array.isArray(raw)) return null;
  const out = raw
    // deno-lint-ignore no-explicit-any
    .map((s: any) => ({
      effort: String(s?.effort ?? ""),
      durationSeconds: num(s?.duration_seconds),
      distanceMiles: num(s?.distance_miles),
      pacePerMile: String(s?.pace_per_mile ?? ""),
    }))
    .filter((s) => s.effort);
  return out.length > 0 ? out : null;
}

// deno-lint-ignore no-explicit-any
export function mapParsedStructure(raw: any): VoiceLogInput["parsedStructure"] {
  if (!raw || typeof raw !== "object") return null;
  const eq = raw.equivalent_race_pace;
  const work = raw.work ?? raw.work_summary;
  const workDist = num(work?.total_work_distance_mi ?? work?.total_distance_mi ?? work?.totalDistanceMi);
  // The per-rep geometry — what the training signal actually reads.
  // `blocks` is snake_case in the column and camelCase in the model, so the
  // mapping is explicit rather than a spread.
  const blocks = Array.isArray(raw.blocks)
    ? (raw.blocks as Array<Record<string, unknown>>)
      .filter((b) => b && typeof b === "object" && b.role)
      .map((b) => ({
        role: String(b.role),
        durationS: numOrNull(b.duration_s),
        distanceMiles: numOrNull(b.distance_miles),
        avgPacePerMile: b.avg_pace_per_mile == null ? null : String(b.avg_pace_per_mile),
        avgHr: numOrNull(b.avg_hr),
        elevationGainM: numOrNull(b.elevation_gain_m ?? b.total_elevation_gain),
      }))
    : null;

  return {
    confidence: num(raw.confidence),
    type: String(raw.type ?? ""),
    equivalentRacePace: eq && eq.pace_per_mile && eq.distance_key
      ? { pacePerMile: String(eq.pace_per_mile), distanceKey: String(eq.distance_key) }
      : null,
    workSummary: workDist > 0 ? { totalDistanceMi: workDist } : null,
    blocks: blocks && blocks.length > 0 ? blocks : null,
    intentPattern: raw.intent_pattern == null ? null : String(raw.intent_pattern),
  };
}

/** timestamptz / date string → "yyyy-MM-dd" (UTC). */
export function toDay(raw: string): string | null {
  if (!raw) return null;
  if (raw.length >= 10 && raw[4] === "-" && raw[7] === "-") return raw.slice(0, 10);
  const d = new Date(raw);
  return Number.isNaN(d.getTime()) ? null : d.toISOString().slice(0, 10);
}

// deno-lint-ignore no-explicit-any
export function num(v: any): number {
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : 0;
}

// deno-lint-ignore no-explicit-any
export function numOrNull(v: any): number | null {
  if (v === null || v === undefined) return null;
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : null;
}

/** training_logs.weather_actual jsonb → model WeatherInput (or null). */
// deno-lint-ignore no-explicit-any
export function mapWeather(raw: any): VoiceLogInput["weather"] {
  if (!raw || typeof raw !== "object") return null;
  const tempF = numOrNull(raw.temp_f);
  const dewPointF = numOrNull(raw.dew_point_f);
  return tempF !== null && dewPointF !== null ? { tempF, dewPointF } : null;
}

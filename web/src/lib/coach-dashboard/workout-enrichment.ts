// Pure enrichment for the coach WorkoutDrawer (redesign 2026-07-16, P1).
//
// These functions reshape rows that from-supabase.ts has ALREADY fetched
// (running_workout_laps, training_logs.weather_actual, the linked
// scheduled_workouts prescription) into the optional WorkoutDetail blocks the
// drawer renders. They touch no database and no React — same testability
// contract as the rule evaluators and workout-helpers.
//
// Every function returns `undefined`/empty when its inputs are too thin, so the
// builder can call them unconditionally and the drawer degrades gracefully.
// No fabrication: captions cite only numbers derived from the rows; the AI
// "read" (§3 row 9) is deliberately NOT produced here — it's a P3 LLM call.

import {
  totalWorkoutMiles,
  totalWorkoutDurationMinutes,
  headlineZone,
  zoneLabelShort,
  paceRangeLabel,
  workoutHasTimeBasedSegment,
  type AthletePaceTable,
  type WorkoutStep,
} from "@/components/coach/workout-helpers";
import type {
  ChartLap,
  WorkoutChart,
  WorkoutConditions,
  WorkoutDetail,
  WorkoutPrescribed,
  WorkoutSplit,
} from "./types";

const METERS_PER_MILE = 1609.344;
const FEET_PER_METER = 3.28084;
const DEW_HOT_F = 68; // adaptation-rules.ts hot threshold

// ── Row shapes (a subset of the real columns the builder selects) ──────────
export interface EnrichLap {
  lap_index: number;
  distance_meters: number | null;
  avg_pace_sec_per_mile: number | null;
  heat_adjusted_pace_sec_per_mile: number | null;
  avg_heart_rate: number | null;
  temp_f: number | null;
  dew_point_f: number | null;
  heat_category: string | null;
  total_elevation_gain: number | null; // meters (Strava convention)
  is_rest?: boolean | null;
}

export interface WeatherActual {
  temp_f?: number | null;
  dew_point_f?: number | null;
  /** Relative humidity, percent. No per-lap average exists for this — it's a
   *  flat read of the run's weather snapshot. */
  humidity?: number | null;
}

// ── Formatters ─────────────────────────────────────────────────────────────
export function fmtPaceSec(sec: number): string {
  const s = Math.max(0, Math.round(sec));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

export function fmtClock(totalSeconds: number): string {
  const s = Math.max(0, Math.round(totalSeconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  return h > 0
    ? `${h}:${String(m).padStart(2, "0")}:${String(sec).padStart(2, "0")}`
    : `${m}:${String(sec).padStart(2, "0")}`;
}

const lapMiles = (l: EnrichLap) => Number(l.distance_meters ?? 0) / METERS_PER_MILE;

// A rep's distance as a compact label: sub-mile reads in metres rounded to the
// nearest 100 ("800m"), a mile or more in miles ("1.0 mi").
function repDistLabel(mi: number): string {
  if (mi < 0.95) return `${Math.round((mi * METERS_PER_MILE) / 100) * 100}m`;
  return `${mi.toFixed(1)} mi`;
}

// Distance-weighted average of a per-lap value (pace, hr) over the laps that
// have both a positive distance and a value. Returns null when nothing weighs in.
function weightedAvg(laps: EnrichLap[], value: (l: EnrichLap) => number | null | undefined): number | null {
  let num = 0;
  let den = 0;
  for (const l of laps) {
    const mi = lapMiles(l);
    const v = value(l);
    if (mi > 0 && v != null && Number(v) > 0) {
      num += Number(v) * mi;
      den += mi;
    }
  }
  return den > 0 ? num / den : null;
}

const hasHeatAdj = (laps: EnrichLap[]) =>
  laps.some((l) => l.heat_adjusted_pace_sec_per_mile != null && Number(l.heat_adjusted_pace_sec_per_mile) > 0);

// ── Prescription (§3 row 1) ─────────────────────────────────────────────────
// Derive the prescribed line from scheduled_workouts.workout_data.steps using
// the same helpers the plan builder uses, so the drawer and the plan agree.
export function buildPrescribed(
  workoutData: { steps?: WorkoutStep[]; name?: string } | null | undefined,
  actualMiles: number,
  athletePaces?: AthletePaceTable,
): WorkoutPrescribed | undefined {
  const steps = workoutData?.steps;
  if (!steps || steps.length === 0) return undefined;

  const distance = Math.round(totalWorkoutMiles(steps) * 10) / 10;
  if (!(distance > 0)) return undefined;

  const zone = headlineZone(steps, athletePaces);
  const label = zone ? zoneLabelShort(zone) : "Session";
  const window = zone ? paceRangeLabel(zone, undefined, undefined, athletePaces) : "";

  const mins = totalWorkoutDurationMinutes(steps, athletePaces);
  const timeEst = mins > 0
    ? `${workoutHasTimeBasedSegment(steps) ? "~" : ""}${fmtClock(mins * 60)}`
    : undefined;

  // Signed miles vs. plan; only surface a cut/extension when it's ≥ 0.5 mi so
  // rounding noise doesn't render a spurious chip.
  const deltaMi = Math.round((actualMiles - distance) * 10) / 10;
  const cutAtMi = Math.abs(deltaMi) >= 0.5 ? deltaMi : undefined;

  return { label, distance, window: window || "", timeEst, cutAtMi };
}

// ── Conditions (§3 row 4) ───────────────────────────────────────────────────
export function buildConditions(
  laps: EnrichLap[],
  weather: WeatherActual | null | undefined,
  startTime?: string,
): WorkoutConditions | undefined {
  const tempAvg = weightedAvg(laps, (l) => l.temp_f);
  const dewAvg = weightedAvg(laps, (l) => l.dew_point_f);
  const tempF = tempAvg ?? (weather?.temp_f != null ? Number(weather.temp_f) : null);
  const dewPointF = dewAvg ?? (weather?.dew_point_f != null ? Number(weather.dew_point_f) : null);
  const hrAvg = weightedAvg(laps, (l) => l.avg_heart_rate);
  const climbM = laps.reduce((s, l) => s + Number(l.total_elevation_gain ?? 0), 0);
  const climbFt = Math.round(climbM * FEET_PER_METER);
  const humidityPct = weather?.humidity != null ? Math.round(Number(weather.humidity)) : undefined;

  // Nothing worth a strip.
  if (tempF == null && dewPointF == null && hrAvg == null && climbFt <= 0 && humidityPct == null) return undefined;

  const dewHot = dewPointF != null && dewPointF > DEW_HOT_F;
  const caption =
    dewHot && dewPointF != null
      ? `Dew point ${Math.round(dewPointF)}° sits past the ${DEW_HOT_F}° hot threshold — every lap carried a heat adjustment.`
      : undefined;

  // Heat cost as a % of raw pace — the same adj/raw weighted averages
  // heatAdjHeadline derives, expressed as a percentage instead of a delta.
  let heatCostPct: number | undefined;
  if (hasHeatAdj(laps)) {
    const adj = weightedAvg(laps, (l) => l.heat_adjusted_pace_sec_per_mile);
    const raw = weightedAvg(laps, (l) => l.avg_pace_sec_per_mile);
    if (adj != null && raw != null && raw > 0) {
      heatCostPct = Math.round(((adj - raw) / raw) * 1000) / 10;
    }
  }

  return {
    tempF: tempF != null ? Math.round(tempF) : 0,
    dewPointF: dewPointF != null ? Math.round(dewPointF) : 0,
    dewHot,
    climbFt,
    hrAvg: hrAvg != null ? Math.round(hrAvg) : 0,
    heatCostPct,
    humidityPct,
    startTime,
    caption,
  };
}

// ── Chart (§3 row 3) ────────────────────────────────────────────────────────
// Cumulative-distance samples from the laps. Elevation is the running sum of
// per-lap gain (we only store gain, not an altitude stream) — a monotone climb
// profile, honest to what we have.
export function buildChart(
  laps: EnrichLap[],
  opts: { bandLow: number; bandHigh: number; plannedMi: number; cutAtMi?: number },
): WorkoutChart | undefined {
  const runLaps = laps.filter((l) => lapMiles(l) > 0 && l.avg_pace_sec_per_mile != null);
  if (runLaps.length < 2) return undefined;

  const samples: ChartLap[] = [];
  let cumMi = 0;
  let cumElevFt = 0;
  // seed a start point at 0
  samples.push({
    mi: 0,
    paceSec: Number(runLaps[0].avg_pace_sec_per_mile),
    adjPaceSec: runLaps[0].heat_adjusted_pace_sec_per_mile != null
      ? Number(runLaps[0].heat_adjusted_pace_sec_per_mile)
      : undefined,
    hr: runLaps[0].avg_heart_rate != null ? Number(runLaps[0].avg_heart_rate) : undefined,
    elevFt: 0,
  });
  for (const l of runLaps) {
    cumMi += lapMiles(l);
    cumElevFt += Number(l.total_elevation_gain ?? 0) * FEET_PER_METER;
    samples.push({
      mi: Math.round(cumMi * 1000) / 1000,
      paceSec: Number(l.avg_pace_sec_per_mile),
      adjPaceSec: l.heat_adjusted_pace_sec_per_mile != null ? Number(l.heat_adjusted_pace_sec_per_mile) : undefined,
      hr: l.avg_heart_rate != null ? Number(l.avg_heart_rate) : undefined,
      elevFt: Math.round(cumElevFt),
    });
  }

  const climbFt = Math.round(cumElevFt);
  return {
    laps: samples,
    bandLow: opts.bandLow,
    bandHigh: opts.bandHigh,
    plannedMi: Math.max(opts.plannedMi, cumMi),
    cutAtMi: opts.cutAtMi,
    climbLabel: climbFt > 0 ? `+${climbFt.toLocaleString()} ft` : undefined,
  };
}

// ── Splits (§3 row 5) ───────────────────────────────────────────────────────
// Long runs bucket into thirds; quality sessions keep one row per work lap.
// Each row carries raw + heat-adjusted pace; a cut adds a "not run" ghost.
export function buildSplits(
  laps: EnrichLap[],
  opts: { isLong: boolean; bandHigh: number; plannedMi: number; ranMi: number },
): { splitLabel: string; splits: WorkoutSplit[] } | undefined {
  const runLaps = laps.filter((l) => lapMiles(l) > 0 && l.avg_pace_sec_per_mile != null && !l.is_rest);
  if (runLaps.length === 0) return undefined;

  const overBand = (sec: number | null) => sec != null && sec > opts.bandHigh;
  const splits: WorkoutSplit[] = [];

  if (opts.isLong && runLaps.length >= 3) {
    // Even thirds by mile boundary.
    const totalMi = runLaps.reduce((s, l) => s + lapMiles(l), 0);
    const third = totalMi / 3;
    const buckets: EnrichLap[][] = [[], [], []];
    let acc = 0;
    let startMi = 0;
    const bounds: Array<[number, number]> = [];
    for (const l of runLaps) {
      const b = Math.min(2, Math.floor(acc / third));
      buckets[b].push(l);
      acc += lapMiles(l);
    }
    for (let i = 0; i < 3; i++) {
      const b = buckets[i];
      if (b.length === 0) continue;
      const miInBucket = b.reduce((s, l) => s + lapMiles(l), 0);
      const endMi = startMi + miInBucket;
      bounds.push([startMi, endMi]);
      const raw = weightedAvg(b, (l) => l.avg_pace_sec_per_mile);
      const adj = weightedAvg(b, (l) => l.heat_adjusted_pace_sec_per_mile);
      const hr = weightedAvg(b, (l) => l.avg_heart_rate);
      splits.push({
        name: `Miles ${Math.round(startMi) + 1}–${Math.round(endMi)}`,
        pace: raw != null ? fmtPaceSec(raw) : null,
        adj: adj != null ? fmtPaceSec(adj) : undefined,
        onTarget: !overBand(raw),
        hrAvg: hr != null ? Math.round(hr) : undefined,
      });
      startMi = endMi;
    }
  } else {
    // Quality session — group the actual laps into warm-up / reps / cool-down.
    // Work laps are the reps (at or faster than the prescribed band, or — when
    // there's no prescription — faster than the run's own median by a margin);
    // the slower leading/trailing laps are the warm-up and cool-down, and the
    // easy laps between reps are recoveries, folded out of the rep list.
    const pace = (l: EnrichLap) => Number(l.avg_pace_sec_per_mile ?? 0);
    const bandKnown = Number.isFinite(opts.bandHigh);
    const sorted = runLaps.map(pace).filter((p) => p > 0).sort((a, b) => a - b);
    const median = sorted.length ? sorted[Math.floor(sorted.length / 2)] : 0;
    const workThreshold = bandKnown ? opts.bandHigh : median - 15;
    const isWork = (l: EnrichLap) => {
      const p = pace(l);
      return p > 0 && p <= workThreshold;
    };

    let firstWork = -1;
    let lastWork = -1;
    runLaps.forEach((l, i) => {
      if (isWork(l)) {
        if (firstWork < 0) firstWork = i;
        lastWork = i;
      }
    });

    if (firstWork < 0) {
      // No lap reads as a rep — fall back to a flat per-lap list.
      for (const l of runLaps) {
        const raw = pace(l) > 0 ? pace(l) : null;
        const adj = l.heat_adjusted_pace_sec_per_mile != null ? Number(l.heat_adjusted_pace_sec_per_mile) : null;
        splits.push({
          name: `Lap ${l.lap_index + 1} · ${lapMiles(l).toFixed(1)} mi`,
          pace: raw != null ? fmtPaceSec(raw) : null,
          adj: adj != null ? fmtPaceSec(adj) : undefined,
          onTarget: !overBand(raw),
          hrAvg: l.avg_heart_rate != null ? Math.round(Number(l.avg_heart_rate)) : undefined,
        });
      }
    } else {
      const aggregate = (laps: EnrichLap[], name: string) => {
        const mi = laps.reduce((s, l) => s + lapMiles(l), 0);
        if (mi <= 0) return;
        const raw = weightedAvg(laps, (l) => l.avg_pace_sec_per_mile);
        const adj = weightedAvg(laps, (l) => l.heat_adjusted_pace_sec_per_mile);
        const hr = weightedAvg(laps, (l) => l.avg_heart_rate);
        splits.push({
          name: `${name} · ${mi.toFixed(1)} mi`,
          pace: raw != null ? fmtPaceSec(raw) : null,
          adj: adj != null ? fmtPaceSec(adj) : undefined,
          onTarget: true, // warm-up / cool-down aren't measured against the band
          hrAvg: hr != null ? Math.round(hr) : undefined,
        });
      };

      aggregate(runLaps.slice(0, firstWork), "Warm-up");
      let rep = 0;
      for (let i = firstWork; i <= lastWork; i++) {
        const l = runLaps[i];
        if (!isWork(l)) continue; // recovery jog between reps
        rep++;
        const raw = pace(l) > 0 ? pace(l) : null;
        const adj = l.heat_adjusted_pace_sec_per_mile != null ? Number(l.heat_adjusted_pace_sec_per_mile) : null;
        splits.push({
          name: `Rep ${rep} · ${repDistLabel(lapMiles(l))}`,
          pace: raw != null ? fmtPaceSec(raw) : null,
          adj: adj != null ? fmtPaceSec(adj) : undefined,
          onTarget: !overBand(raw),
          hrAvg: l.avg_heart_rate != null ? Math.round(Number(l.avg_heart_rate)) : undefined,
        });
      }
      aggregate(runLaps.slice(lastWork + 1), "Cool-down");
    }
  }

  // Cut → a single ghost row for the unrun tail.
  const unrun = Math.round((opts.plannedMi - opts.ranMi) * 10) / 10;
  if (unrun >= 0.5) {
    const from = Math.round(opts.ranMi) + 1;
    const to = Math.round(opts.plannedMi);
    splits.push({
      name: to > from ? `Miles ${from}–${to}` : `Mile ${from}`,
      pace: null,
      onTarget: false,
    });
  }

  const splitLabel = hasHeatAdj(runLaps) ? "Splits · heat-adj · raw" : "Splits";
  return { splitLabel, splits };
}

// ── Heat-adjusted headline cell (§3 row 2, 4th cell) ────────────────────────
// The distance-weighted heat-adjusted pace across the run, with its delta to
// raw and whether it lands in the prescribed band.
export function heatAdjHeadline(
  laps: EnrichLap[],
  band: { low: number; high: number } | undefined,
): { v: string; sub: string } | undefined {
  if (!hasHeatAdj(laps)) return undefined;
  const adj = weightedAvg(laps, (l) => l.heat_adjusted_pace_sec_per_mile);
  const raw = weightedAvg(laps, (l) => l.avg_pace_sec_per_mile);
  if (adj == null) return undefined;
  const parts: string[] = [];
  if (raw != null) {
    const delta = Math.round(adj - raw);
    parts.push(`**${delta <= 0 ? "−" : "+"}${Math.abs(delta)}s**`);
  }
  if (band) parts.push(adj <= band.high ? "in band" : "over band");
  return { v: `${fmtPaceSec(adj)}/mi`, sub: parts.join(" · ") };
}

// Convenience: assemble the headline 4-stat strip from actual + prescribed +
// heat-adj. Distance/Time/Pace always render; heat-adj only when derivable.
export function buildHeadlineKpis(args: {
  actualMiles: number;
  plannedMiles?: number;
  durationSec?: number;
  timeEst?: string;
  paceLabel?: string;
  window?: string;
  heatAdj?: { v: string; sub: string };
}): WorkoutDetail["kpis"] {
  const kpis: WorkoutDetail["kpis"] = [
    {
      k: "Distance",
      v: `${args.actualMiles % 1 === 0 ? args.actualMiles : args.actualMiles.toFixed(1)} mi`,
      sub: args.plannedMiles ? `of **${args.plannedMiles}** planned` : undefined,
    },
    {
      k: "Time",
      v: args.durationSec ? fmtClock(args.durationSec) : "—",
      sub: args.timeEst ? `planned **${args.timeEst}**` : undefined,
    },
    {
      k: "Pace",
      v: args.paceLabel ?? "—",
      sub: args.window ? `vs **${args.window}**` : undefined,
    },
  ];
  if (args.heatAdj) {
    kpis.push({ k: "Heat-adj", v: args.heatAdj.v, sub: args.heatAdj.sub, accent: true });
  }
  return kpis;
}

// Verdict-as-title (§2, reading order): a sentence-case title with a period,
// in the Post Run Drip voice. Only overrides the default label when the run was
// CUT short of its prescription — that's the verdict worth leading with. Returns
// undefined otherwise, so the drawer falls back to the normal label.
export function verdictTitle(typeLabel: string, actualMi: number, plannedMi?: number): string | undefined {
  if (plannedMi != null && actualMi + 0.05 < plannedMi) {
    const at = actualMi % 1 === 0 ? `${actualMi}` : actualMi.toFixed(1);
    return `${typeLabel}, cut at ${at}.`;
  }
  return undefined;
}

// Parse the band edges (seconds/mile) from a prescribed window like "8:55–9:25".
export function parseBand(window: string | undefined): { low: number; high: number } | undefined {
  if (!window) return undefined;
  const m = window.match(/(\d+):(\d{2})\s*[–\-]\s*(\d+):(\d{2})/);
  if (!m) {
    const single = window.match(/(\d+):(\d{2})/);
    if (!single) return undefined;
    const s = Number(single[1]) * 60 + Number(single[2]);
    return { low: s, high: s };
  }
  const a = Number(m[1]) * 60 + Number(m[2]);
  const b = Number(m[3]) * 60 + Number(m[4]);
  return { low: Math.min(a, b), high: Math.max(a, b) };
}

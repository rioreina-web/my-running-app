/**
 * trends-insights — per-second stream helpers (Group B).
 *
 * Pure functions over a normalized `StreamRun`. All the inside-the-run math
 * lives here so the B detectors stay declarative and unit-testable without
 * touching real blobs. No IO, no `Date.now()`.
 *
 * `external_streams` is a JSONB column on `training_logs`, Strava-shaped.
 * Two shapes exist in the wild: arrays at the top level (`es.heartrate`)
 * and arrays nested under `es.streams` (`es.streams.heartrate`). `normalize`
 * handles both.
 */

const METERS_PER_MILE = 1609.34;

/** A run's per-second streams, index-aligned. Missing streams are []. */
export interface StreamRun {
  logId: string;
  date: string; // workout_date
  type: string | null;
  /** Index into the timeline's week windows, or -1 if outside. */
  weekIndex: number;
  weekLabel: string;
  time: number[]; // seconds
  hr: number[]; // bpm
  vel: number[]; // m/s (velocity_smooth)
  cadence: number[]; // spm
  /** Work-rep end indices (from running_workout_laps), for HRR60. */
  repEndIdx: number[];
}

type RawStreams = Record<string, unknown>;

function asNumArray(v: unknown): number[] {
  return Array.isArray(v) ? (v.filter((x) => typeof x === "number") as number[]) : [];
}

/** Pull a named per-second array, top-level or nested under `streams`. */
export function pickStream(es: RawStreams, key: string): number[] {
  const top = asNumArray(es[key]);
  if (top.length > 0) return top;
  const nested = (es.streams as RawStreams | undefined)?.[key];
  return asNumArray(nested);
}

/** sec/mile from m/s. Infinity when stopped/invalid (so it lands in no band). */
export function paceSecFromVel(velMps: number): number {
  return velMps > 0 ? METERS_PER_MILE / velMps : Infinity;
}

/** The 30-sec/mi pace band a pace falls in (e.g. 525 → 510 for the 8:30–9:00). */
export function band30(paceSec: number): number {
  return Math.floor(paceSec / 30) * 30;
}

/** Plausible running pace (5:00–12:00 /mi) — excludes walking, GPS stalls, sprints. */
function isRunningPace(paceSec: number): boolean {
  return paceSec >= 300 && paceSec <= 720;
}

/**
 * The athlete's most-populated running pace band across the given runs, and
 * how many seconds live in it. Null when there isn't enough running data.
 */
export function modalBand(runs: StreamRun[]): { band: number; seconds: number } | null {
  const counts = new Map<number, number>();
  for (const run of runs) {
    for (let i = 0; i < run.vel.length; i++) {
      const p = paceSecFromVel(run.vel[i]);
      if (!isRunningPace(p)) continue;
      const b = band30(p);
      counts.set(b, (counts.get(b) ?? 0) + 1);
    }
  }
  let best: number | null = null;
  let bestN = 0;
  for (const [b, n] of counts) {
    if (n > bestN) {
      best = b;
      bestN = n;
    }
  }
  return best == null ? null : { band: best, seconds: bestN };
}

/** Sum + count of HR seconds inside a pace band, for one run. */
export function hrInBand(run: StreamRun, band: number): { sum: number; n: number } {
  let sum = 0;
  let n = 0;
  const len = Math.min(run.vel.length, run.hr.length);
  for (let i = 0; i < len; i++) {
    if (run.hr[i] <= 0) continue;
    const p = paceSecFromVel(run.vel[i]);
    if (!isRunningPace(p)) continue;
    if (band30(p) === band) {
      sum += run.hr[i];
      n += 1;
    }
  }
  return { sum, n };
}

/**
 * Aerobic decoupling for one run, as a percentage. Splits the run in half by
 * sample count; for each half computes the HR-per-speed ratio (beats spent
 * per unit speed); returns how much that ratio rose in the back half.
 * ~5% is the classic durability line. Null when HR/velocity are too sparse.
 */
export function decouplingPct(run: StreamRun): number | null {
  const len = Math.min(run.hr.length, run.vel.length);
  if (len < 600) return null; // < 10 min of paired data — not a long run
  const mid = Math.floor(len / 2);

  const ratio = (lo: number, hi: number): number | null => {
    let hrSum = 0;
    let velSum = 0;
    let n = 0;
    for (let i = lo; i < hi; i++) {
      const p = paceSecFromVel(run.vel[i]);
      if (run.hr[i] <= 0 || !isRunningPace(p)) continue;
      hrSum += run.hr[i];
      velSum += run.vel[i];
      n += 1;
    }
    if (n < 60 || velSum <= 0) return null;
    return (hrSum / n) / (velSum / n); // beats per (m/s)
  };

  const r1 = ratio(0, mid);
  const r2 = ratio(mid, len);
  if (r1 == null || r2 == null || r1 === 0) return null;
  return ((r2 - r1) / r1) * 100;
}

/** Cadence fade: mean cadence(final third) − mean cadence(first third). Null if sparse. */
export function cadenceFade(run: StreamRun): number | null {
  const c = run.cadence.filter((x) => x > 0);
  if (c.length < 300) return null;
  const third = Math.floor(c.length / 3);
  const mean = (lo: number, hi: number) => {
    let s = 0;
    for (let i = lo; i < hi; i++) s += c[i];
    return s / (hi - lo);
  };
  return mean(c.length - third, c.length) - mean(0, third);
}

/**
 * HR recovery over 60s after each rep, averaged for one run. For every work-
 * rep end index, HR(end) − HR(end + 60s). Higher = bouncing back faster.
 * Null when there are no reps or no post-rep HR to compare.
 */
export function hrr60(run: StreamRun): number | null {
  const drops: number[] = [];
  for (const end of run.repEndIdx) {
    const after = end + 60;
    if (end < 0 || after >= run.hr.length) continue;
    const a = run.hr[end];
    const b = run.hr[after];
    if (a > 0 && b > 0 && a > b) drops.push(a - b);
  }
  if (drops.length === 0) return null;
  return drops.reduce((x, y) => x + y, 0) / drops.length;
}

/** "8:30" from 510 sec/mi (band label). */
export function bandLabel(band: number): string {
  return `${Math.floor(band / 60)}:${String(band % 60).padStart(2, "0")}`;
}

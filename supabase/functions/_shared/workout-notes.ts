/**
 * Derive a runner-readable workout description ("6×800m @ 2:35 w/ 90s rec")
 * from rep-level laps, for the FALLBACK case where the athlete didn't describe
 * the session in a voice memo. The voice memo is always primary; this only
 * fills training_logs.workout_notes when it's empty, so the app still knows
 * WHAT the workout was (needed to evaluate it).
 *
 * Pure + dependency-free → unit tested in workout-notes.test.ts.
 */
import type { LapInput, SegmentationResult } from "./workoutSegmentation.ts";

function avg(xs: number[]): number {
  return xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : 0;
}

/** mm:ss for ≥60s, else "Ns". Used for rep times and recovery. */
export function fmtClock(seconds: number): string {
  const s = Math.round(seconds);
  if (s < 60) return `${s}s`;
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

/** Snap a rep distance (meters) to a common label. `sub` = shorter than a mile
 *  (expressed as a rep TIME), else expressed as pace/mile. */
export function snapRepDistance(meters: number): { key: string; label: string; sub: boolean } {
  const commons = [200, 300, 400, 500, 600, 800, 1000, 1200, 1600, 2000, 3000, 5000];
  for (const c of commons) {
    if (Math.abs(meters - c) <= Math.max(25, c * 0.06)) {
      return { key: `${c}m`, label: `${c}m`, sub: c < 1609 };
    }
  }
  const miles = meters / 1609.344;
  const rounded = Math.round(miles);
  if (rounded >= 1 && Math.abs(miles - rounded) < 0.08) {
    return { key: `${rounded}mi`, label: `${rounded}mi`, sub: false };
  }
  return { key: `${miles.toFixed(2)}mi`, label: `${miles.toFixed(2)}mi`, sub: false };
}

/** Derive a structure line ("6×800m @ 2:35 w/ 90s rec") from laps for a
 *  structured rep session. Returns null for continuous easy/steady/long runs
 *  (no fabricated structure) or when laps can't support a confident read. */
export function deriveWorkoutNotes(
  seg: Pick<SegmentationResult, "workoutKind" | "repCount">,
  laps: LapInput[] | undefined,
): string | null {
  if (!laps || laps.length === 0) return null;
  // Only auto-describe rep workouts — a steady or easy run has no "structure"
  // worth fabricating, and the stat row already carries its pace + distance.
  const repKinds = new Set(["intervals", "threshold", "tempo", "fartlek", "progression"]);
  if (!repKinds.has(seg.workoutKind) || seg.repCount < 2) return null;

  // Plausible work laps — used only to find the fastest rep pace, which gates
  // out unflagged recovery jogs below.
  const workish = laps.filter((l) =>
    l.is_rest !== true &&
    Number(l.distance_meters ?? 0) >= 150 &&
    Number(l.moving_time_seconds ?? 0) >= 20 &&
    Number(l.avg_pace_sec_per_mile ?? 0) > 0
  );
  if (workish.length < 2) return null;
  const fastest = Math.min(...workish.map((l) => Number(l.avg_pace_sec_per_mile)));

  // A lap is a recovery/boundary when it's flagged rest, too small to be a work
  // lap, or much slower than the fastest rep (an unflagged float/jog).
  const isRecovery = (l: LapInput): boolean => {
    if (l.is_rest === true) return true;
    const d = Number(l.distance_meters ?? 0);
    const t = Number(l.moving_time_seconds ?? 0);
    const p = Number(l.avg_pace_sec_per_mile ?? 0);
    if (!(d >= 150 && t >= 20 && p > 0)) return true;
    return p > fastest * 1.5;
  };

  // Merge consecutive work laps with NO recovery between them into one rep.
  // The core rule of rep structure: a rep is bounded by a recovery, not by a
  // distance marker. A continuous 2k auto-lapped as two 1k splits is ONE 2k
  // rep, not "2×1000m". Mirrors detectWorkBouts() so the notes agree with the
  // parsed structure (intent_pattern) on every screen.
  type Rep = { dist: number; time: number };
  const reps: Rep[] = [];
  let cur: Rep | null = null;
  for (const lap of laps) {
    if (isRecovery(lap)) { cur = null; continue; }
    const d = Number(lap.distance_meters);
    const t = Number(lap.moving_time_seconds);
    if (cur) { cur.dist += d; cur.time += t; }
    else { cur = { dist: d, time: t }; reps.push(cur); }
  }
  if (reps.length < 2) return null;

  // Trim warmup/cooldown from the ENDS: leading or trailing reps much slower
  // than the work-pace band aren't part of the rep set (a 7:30 warmup mile, a
  // jog-home cooldown). Middle reps are kept even if slower — a hard session
  // can have one rough rep. Pace = sec/mile from the merged rep.
  const repPace = (r: Rep) => (r.time > 0 ? (1609.344 * r.time) / r.dist : Infinity);
  const sortedPaces = reps.map(repPace).sort((a, b) => a - b);
  // Median rep pace is the work anchor. Using the median (not the fastest reps)
  // keeps a mixed session honest: faster strides shouldn't make the main
  // threshold reps look like warmup. We only trim ends SLOWER than the band, so
  // faster reps are never dropped.
  const workPace = sortedPaces[Math.floor((sortedPaces.length - 1) / 2)];
  const band = workPace * 1.15;
  let lo = 0, hi = reps.length - 1;
  while (lo < hi && repPace(reps[lo]) > band) lo++;
  while (hi > lo && repPace(reps[hi]) > band) hi--;
  const trimmed = reps.slice(lo, hi + 1);
  if (trimmed.length < 2) return null;

  // Group consecutive same-distance reps → "2000m", "2×1000m", "4×1mi", etc.
  const groups: Array<{ key: string; label: string; sub: boolean; reps: Rep[] }> = [];
  for (const rep of trimmed) {
    const snap = snapRepDistance(rep.dist);
    const last = groups[groups.length - 1];
    if (last && last.key === snap.key) last.reps.push(rep);
    else groups.push({ key: snap.key, label: snap.label, sub: snap.sub, reps: [rep] });
  }

  const parts = groups.map((g) => {
    const n = g.reps.length;
    const count = n > 1 ? `${n}×` : "";
    if (g.sub) {
      // sub-mile reps read as rep TIME ("2×1000m @ 3:12")
      const t = avg(g.reps.map((r) => r.time));
      return `${count}${g.label} @ ${fmtClock(t)}`;
    }
    // mile+ reps read as pace/mile ("2000m @ 5:17/mi"), computed from the
    // merged rep's distance + time so a stitched-together 2k is paced as a 2k.
    const p = avg(g.reps.map((r) => (r.time > 0 ? (1609.344 * r.time) / r.dist : 0)));
    return `${count}${g.label} @ ${fmtClock(p)}/mi`;
  });
  if (parts.length === 0) return null;

  let line = parts.join(" + ");

  // Recovery: the typical SHORT inter-rep rest. Filter to plausible recoveries
  // (10–180s) so long between-set standing gaps, a stop at a light, or GPS
  // blips don't dominate, then take the median. Only reported with ≥2 such
  // rests. Rendered the way runners say it under 2 min ("90s rec"), mm:ss above.
  const shortRests = laps
    .filter((l) => l.is_rest === true)
    .map((l) => Number(l.moving_time_seconds ?? 0))
    .filter((s) => s >= 20 && s <= 180)
    .sort((a, b) => a - b);
  if (shortRests.length >= 2) {
    const r = Math.round(shortRests[Math.floor((shortRests.length - 1) / 2)]);
    line += ` w/ ${r < 120 ? `${r}s` : fmtClock(r)} rec`;
  }

  return line;
}

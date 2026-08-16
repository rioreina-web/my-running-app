import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  boutsFromLaps,
  detectWorkBouts,
  formatWorkBouts,
  type LapInput,
  lapRoles,
  nearestRepDistance,
  nearestTimeRep,
  RawStreams,
  structureHasSpeedContrast,
  WorkBout,
  workBoutCount,
} from "./workBouts.ts";

/**
 * Build a per-second stream from a list of phases. Each phase is a constant
 * velocity held for a number of seconds. distance accumulates vel * 1s.
 */
function buildStream(phases: Array<{ vel: number; secs: number }>): RawStreams {
  const time: number[] = [];
  const distance: number[] = [];
  const velocity_smooth: number[] = [];
  let t = 0;
  let d = 0;
  for (const ph of phases) {
    for (let i = 0; i < ph.secs; i++) {
      time.push(t);
      distance.push(d);
      velocity_smooth.push(ph.vel);
      d += ph.vel; // 1 second steps
      t += 1;
    }
  }
  return { time, distance, velocity_smooth };
}

const works = (segs: ReturnType<typeof detectWorkBouts>["segments"]) =>
  segs.filter((s): s is WorkBout => s.kind === "work");

Deno.test("workBouts: empty / too-short input → no segments", () => {
  assertEquals(detectWorkBouts({}).segments, []);
  assertEquals(detectWorkBouts({ time: [0], distance: [0], velocity_smooth: [5] }).segments, []);
});

Deno.test("workBouts: TWO fast 1-mile splits with NO recovery = ONE 2-mile rep", () => {
  // 5.0 m/s for 644s ≈ 3220m ≈ 2.0 miles, run straight through (no rest).
  const stream = buildStream([{ vel: 5.0, secs: 644 }]);
  const { segments } = detectWorkBouts(stream);
  const w = works(segments);
  assertEquals(w.length, 1, "continuous effort must be a single bout");
  // ~3220m, i.e. one 2-mile rep, NOT two 1-mile reps
  assert(w[0].distance_m > 3000 && w[0].distance_m < 3400, `got ${w[0].distance_m}m`);
  assertEquals(segments.filter((s) => s.kind === "recovery").length, 0);
});

Deno.test("workBouts: two 1-mile efforts WITH a 60s standing rest = TWO reps", () => {
  const mile = { vel: 5.0, secs: 322 }; // ~1610m
  const stream = buildStream([mile, { vel: 0.2, secs: 60 }, mile]);
  const { segments } = detectWorkBouts(stream);
  const w = works(segments);
  assertEquals(w.length, 2, "a real recovery splits the reps");
  const recs = segments.filter((s) => s.kind === "recovery");
  assertEquals(recs.length, 1);
  assertEquals(recs[0].kind === "recovery" && recs[0].style, "standing");
  // each rep ~1 mile
  for (const b of w) assert(b.distance_m > 1450 && b.distance_m < 1750, `got ${b.distance_m}m`);
});

Deno.test("workBouts: a jog recovery (slow but moving) still splits, tagged 'jog'", () => {
  const km = { vel: 5.0, secs: 200 }; // 1000m
  const jog = { vel: 2.2, secs: 90 }; // 198m slow float — below 0.7*work
  const stream = buildStream([km, jog, km]);
  const { segments } = detectWorkBouts(stream);
  assertEquals(works(segments).length, 2);
  const rec = segments.find((s) => s.kind === "recovery");
  assert(rec && rec.kind === "recovery" && rec.style === "jog");
});

Deno.test("workBouts: a brief GPS dip inside a rep does NOT fracture it", () => {
  // 1k fast, a single 5s near-stop (GPS glitch), 1k fast — still ONE rep
  const stream = buildStream([
    { vel: 5.0, secs: 200 },
    { vel: 0.3, secs: 5 },
    { vel: 5.0, secs: 200 },
  ]);
  const { segments } = detectWorkBouts(stream);
  assertEquals(works(segments).length, 1, "a <20s dip is noise, not a recovery");
});

Deno.test("workBouts: reproduces the real session shape — 2K opener then reps", () => {
  // Mirrors fdff3fcb: 2.0km continuous, then fast bouts separated by rests.
  const fast = (m: number) => ({ vel: 5.1, secs: Math.round(m / 5.1) });
  const rest = (s: number) => ({ vel: 0.3, secs: s });
  const stream = buildStream([
    fast(2000), rest(137),
    fast(800), rest(96),
    fast(1000), rest(94),
    fast(1800), rest(130),
    fast(800), rest(89),
    fast(800),
  ]);
  const { segments, workVelMs } = detectWorkBouts(stream);
  const w = works(segments);
  assertEquals(w.length, 6, "six recovery-bounded work bouts");
  // The opener is one continuous ~2km block (the "two 1ks with no rest = 2K")
  assert(w[0].distance_m > 1900 && w[0].distance_m < 2100, `opener ${w[0].distance_m}m`);
  // Five recoveries between the six bouts
  assertEquals(segments.filter((s) => s.kind === "recovery").length, 5);
  // Work pace baseline is sane (~5 m/s)
  assert(workVelMs > 4.5 && workVelMs < 5.6, `workVel ${workVelMs}`);
});

Deno.test("workBouts (GPS): FAST jog recoveries (only ~22% slower) still separate reps", () => {
  // A manually-entered / lapless run of the same session type as Tuesday:
  // 6 × 1mi @ ~5:32 (4.85 m/s) with ~400m jog recoveries @ ~7:04 (3.8 m/s). The
  // recoveries sit ABOVE the old 0.7×work cutoff, so the fixed rule merged the
  // whole thing into one block. The two speed clusters are detected from the
  // velocity distribution instead.
  const rep = { vel: 4.85, secs: 330 };
  const jog = { vel: 3.8, secs: 100 };
  const stream = buildStream([rep, jog, rep, jog, rep, jog, rep, jog, rep, jog, rep]);
  const { segments } = detectWorkBouts(stream);
  assertEquals(works(segments).length, 6, "fast recoveries must still separate the reps");
  assertEquals(segments.filter((s) => s.kind === "recovery").length, 5);
});

Deno.test("workBouts (GPS): fast recoveries with accel/decel ramps still give clean reps", () => {
  // Real GPS has transition seconds between rep and recovery. Those must not
  // fill the valley enough to merge, nor fracture a rep.
  const rep = { vel: 4.85, secs: 300 };
  const jog = { vel: 3.8, secs: 90 };
  const phases: Array<{ vel: number; secs: number }> = [];
  for (let i = 0; i < 5; i++) {
    phases.push(rep, { vel: 4.5, secs: 4 }, { vel: 4.1, secs: 4 }, jog, { vel: 4.1, secs: 4 }, { vel: 4.5, secs: 4 });
  }
  phases.push(rep);
  const { segments } = detectWorkBouts(buildStream(phases));
  assertEquals(works(segments).length, 6, "ramps must neither fragment nor merge the reps");
});

Deno.test("workBouts (GPS): a stepped progression is NOT split into fake work/recovery", () => {
  // Five equal blocks getting faster, no recovery — one continuous progression.
  // The distribution is multi-modal, not two-cluster, so it must not be split.
  const stream = buildStream([
    { vel: 4.3, secs: 200 },
    { vel: 4.5, secs: 200 },
    { vel: 4.7, secs: 200 },
    { vel: 4.9, secs: 200 },
    { vel: 5.1, secs: 200 },
  ]);
  const { segments } = detectWorkBouts(stream);
  assertEquals(segments.filter((s) => s.kind === "recovery").length, 0, "no fabricated recovery");
  assertEquals(works(segments).length, 1, "stays one continuous bout");
});

Deno.test("nearestRepDistance: snaps a measured bout to the standard rep", () => {
  assertEquals(nearestRepDistance(1003).label, "1k");
  assertEquals(nearestRepDistance(1610).label, "1mi");
  assertEquals(nearestRepDistance(2007).label, "2k");
  assertEquals(nearestRepDistance(795).label, "800m");
  assertEquals(nearestRepDistance(3200).label, "2mi"); // 3219m
});

Deno.test("nearestRepDistance: split unit ≠ rep unit — a ~1k bout reads 1k regardless of mile laps", () => {
  // Watch lapped in miles, but the rep is 1k. The bout's true length decides.
  const km = nearestRepDistance(1008);
  assertEquals(km.label, "1k");
  assert(Math.abs(km.delta_pct ?? 99) <= 12);
});

Deno.test("nearestRepDistance: ragged effort → no confident snap (defer to notes)", () => {
  // 1300m: nearest is 1200m at 8.3% (within tol) → snaps to 1200m.
  assertEquals(nearestRepDistance(1300).label, "1200m");
  // 700m: nearest is 800m at 12.5% (> 12% tol) → too ragged to snap.
  assertEquals(nearestRepDistance(700).label, null);
  // 1850m: nearest is 2k at 7.5% → snaps to 2k.
  assertEquals(nearestRepDistance(1850).label, "2k");
});

Deno.test("nearestRepDistance: 1.5k vs 1mi flagged ambiguous", () => {
  const r = nearestRepDistance(1555); // between 1500 and 1609
  assert(r.ambiguous, "1.5k and 1mi are both within tolerance");
});

Deno.test("nearestTimeRep: snaps a bout duration to a time-based rep", () => {
  assertEquals(nearestTimeRep(602).label, "10'");
  assertEquals(nearestTimeRep(298).label, "5'");
  assertEquals(nearestTimeRep(censusSecs(8)).label, "8'");
  assertEquals(nearestTimeRep(125).label, "2'");
  assertEquals(nearestTimeRep(7).label, null); // way under 30" tol
});

function censusSecs(min: number) { return min * 60; }

Deno.test("nearestTimeRep: a 10' tempo rep snaps to 10' regardless of distance covered", () => {
  // ~10 min at ~4:00/km covers ~2.5km — by distance that's not a clean rep,
  // but by time it's a clean 10'. Time lens resolves it.
  const t = nearestTimeRep(600);
  assertEquals(t.label, "10'");
  assert(Math.abs(t.delta_pct ?? 99) <= 12);
});

Deno.test("workBouts: a 10-minute tempo bout shows a clean by-time snap", () => {
  // 10 min continuous at tempo (4.2 m/s ≈ 2520m), then a 90s jog, then another.
  const tempo = { vel: 4.2, secs: 600 };
  const stream = buildStream([tempo, { vel: 2.0, secs: 90 }, tempo]);
  const { segments } = detectWorkBouts(stream);
  const out = formatWorkBouts(segments);
  assert(out.includes("by time ≈ 10'"), out);
  assertEquals(works(segments).length, 2);
});

Deno.test("workBouts: formatWorkBouts renders bouts + indented recoveries", () => {
  const stream = buildStream([
    { vel: 5.0, secs: 322 },
    { vel: 0.2, secs: 60 },
    { vel: 5.0, secs: 322 },
  ]);
  const { segments } = detectWorkBouts(stream);
  const out = formatWorkBouts(segments);
  assert(out.includes("Bout 1:"));
  assert(out.includes("Bout 2:"));
  assert(out.includes("recovery:"));
  assertEquals(formatWorkBouts([]), "");
});

// ── boutsFromLaps: the athlete's own watch laps as the segmentation source ──

const lapWorks = (segs: ReturnType<typeof boutsFromLaps>["segments"]) =>
  segs.filter((s): s is WorkBout => s.kind === "work");

// A real recorded session: "3k tempo + 3 × (1k, 600m)". The watch auto-lapped
// the tempo every 1 km (3 fast laps) and recorded each rep + jog recovery as
// its own lap. The GPS re-segmentation diluted every pace and merged warmup
// into the tempo; the laps are crisp. This is the workout that motivated the fn.
const REAL_SESSION: LapInput[] = [
  { distance: 1000, moving_time: 201, average_speed: 4.98 }, // tempo km 1
  { distance: 1000, moving_time: 211, average_speed: 4.74 }, // tempo km 2
  { distance: 1000, moving_time: 220, average_speed: 4.55 }, // tempo km 3
  { distance: 645, moving_time: 280, average_speed: 2.30 },  // recovery
  { distance: 1000, moving_time: 192, average_speed: 5.21 }, // 1k
  { distance: 206, moving_time: 83, average_speed: 2.48 },   // recovery
  { distance: 599, moving_time: 112, average_speed: 5.35 },  // 600
  { distance: 243, moving_time: 183, average_speed: 1.33 },  // recovery
  { distance: 1000, moving_time: 188, average_speed: 5.32 }, // 1k
  { distance: 208, moving_time: 113, average_speed: 1.84 },  // recovery
  { distance: 601, moving_time: 111, average_speed: 5.41 },  // 600
  { distance: 218, moving_time: 192, average_speed: 1.14 },  // recovery
  { distance: 1000, moving_time: 188, average_speed: 5.32 }, // 1k
  { distance: 210, moving_time: 104, average_speed: 2.02 },  // recovery
  { distance: 602, moving_time: 104, average_speed: 5.79 },  // 600
  { distance: 150, moving_time: 434, average_speed: 0.35 },  // cooldown / stop
];

Deno.test("boutsFromLaps: merges tempo laps, keeps reps, trims cooldown", () => {
  const { segments } = boutsFromLaps(REAL_SESSION);
  const w = lapWorks(segments);
  assertEquals(w.length, 7, "3k tempo + 6 interval reps = 7 work bouts");
  // Bout 1 is the whole tempo, merged from 3 laps — NOT split into 3× 1k.
  assertEquals(w[0].distance_m, 3000);
  assertEquals(w[0].duration_s, 632);
  assertEquals(w[0].avg_pace_per_mile, "5:39");
  // The reps carry their true (fast) paces, not the GPS-diluted ones.
  assertEquals(w[6].avg_pace_per_mile, "4:38"); // last 600
  // The trailing 150m stop is a cooldown, not a rep — trimmed.
  assertEquals(segments[segments.length - 1].kind, "work");
});

// A REAL recorded session (Strava activity 19404031188): 6 × 1 mile with ~400m
// jog recoveries. The athlete is fast — reps at ~5:25-5:34/mi — and the jog
// recoveries are EASY, not slow: ~6:22-7:04/mi, only ~15-25% slower than the
// reps. Lap 6 also carries a ~21s water-break auto-pause (elapsed 129 / moving
// 108). The fixed "recovery = below 70% of work pace" rule mislabeled every
// recovery as more work and glued the reps together; the only place it ever
// dipped slow enough was the water break, so the session collapsed into TWO
// continuous blocks split at the water stop. The watch laps encode the true
// structure — trust their fast/slow alternation. (Strava laps carry no
// average_speed here, so velocity is derived from distance / moving_time.)
const MILE_REPEATS_FAST_RECOVERIES: LapInput[] = [
  { distance: 1609.34, moving_time: 328 }, // mile rep 1  (~5:29/mi)
  { distance: 412.92, moving_time: 98 },   // recovery jog (~6:22/mi)
  { distance: 1609.34, moving_time: 325 }, // mile rep 2  (~5:25/mi)
  { distance: 424.7, moving_time: 103 },   // recovery jog (~6:31/mi)
  { distance: 1609.34, moving_time: 333 }, // mile rep 3  (~5:34/mi)
  { distance: 409.2, moving_time: 108 },   // recovery jog — WATER BREAK here
  { distance: 1609.34, moving_time: 334 }, // mile rep 4  (~5:35/mi)
  { distance: 414.41, moving_time: 100 },  // recovery jog
  { distance: 1609.34, moving_time: 316 }, // mile rep 5  (~5:17/mi)
  { distance: 406.99, moving_time: 102 },  // recovery jog
  { distance: 1609.34, moving_time: 331 }, // mile rep 6  (~5:32/mi)
  { distance: 335.63, moving_time: 97 },   // trailing partial recovery
  { distance: 12.55, moving_time: 9 },     // trailing GPS fragment (auto-lap tick)
];

Deno.test("boutsFromLaps: mile repeats with FAST jog recoveries + a water break → 6 reps, not 2", () => {
  const { segments } = boutsFromLaps(MILE_REPEATS_FAST_RECOVERIES);
  const w = lapWorks(segments);
  assertEquals(w.length, 6, "six mile reps — fast recoveries must still separate them");
  // Each work bout is ~1 mile (a rep), not a multi-mile merged block.
  for (const b of w) {
    assert(b.distance_m > 1500 && b.distance_m < 1700, `rep ${b.index} = ${b.distance_m}m`);
  }
  // Five jog recoveries sit between the six reps (trailing partial + the 12m
  // fragment are trimmed, not counted as separators).
  assertEquals(segments.filter((s) => s.kind === "recovery").length, 5);
  // The 21s water-break auto-pause must NOT be the thing that defines structure.
  assert(w.length !== 2, "must not collapse into two water-break-split blocks");
});

Deno.test("boutsFromLaps: a steady run collapses to < 2 bouts (caller falls back)", () => {
  // Five even ~1 mi laps, no recovery — a steady run auto-lapped by distance.
  const steady: LapInput[] = Array.from({ length: 5 }, () => ({
    distance: 1609, moving_time: 480, average_speed: 3.35,
  }));
  const { segments } = boutsFromLaps(steady);
  assert(workBoutCount(segments) < 2, "no rep structure → gate fails → GPS fallback");
});

Deno.test("boutsFromLaps: too few laps → no segments", () => {
  assertEquals(boutsFromLaps([]).segments, []);
  assertEquals(boutsFromLaps([{ distance: 1000, moving_time: 200 }]).segments, []);
});

// ── lapRoles: descriptive per-lap labels, every lap kept ──────────────────

// The real July 24 8×200m shape (rounded from the watch): 2mi warmup, then
// 8 fast ~200m reps each followed by a slow recovery jog, then cooldown.
// The reps measure 196–204m — the OLD `distance < 200` rule flagged three of
// them as rest and the app hid them. lapRoles must label all 8 as reps.
const JUL24_LAPS: LapInput[] = [
  { lap_index: 1, distance: 1609, moving_time: 511 }, // warmup mi
  { lap_index: 2, distance: 1609, moving_time: 457 }, // warmup mi
  { lap_index: 3, distance: 32,  moving_time: 16 },   // tiny transition
  { lap_index: 4, distance: 197, moving_time: 32 },   // rep 1 (sub-200!)
  { lap_index: 5, distance: 65,  moving_time: 61 },   // recovery
  { lap_index: 6, distance: 196, moving_time: 32 },   // rep 2 (sub-200!)
  { lap_index: 7, distance: 58,  moving_time: 60 },   // recovery
  { lap_index: 8, distance: 200, moving_time: 32 },   // rep 3
  { lap_index: 9, distance: 67,  moving_time: 58 },   // recovery
  { lap_index: 10, distance: 202, moving_time: 32 },  // rep 4
  { lap_index: 11, distance: 50,  moving_time: 60 },  // recovery
  { lap_index: 12, distance: 203, moving_time: 30 },  // rep 5
  { lap_index: 13, distance: 85,  moving_time: 61 },  // recovery
  { lap_index: 14, distance: 204, moving_time: 32 },  // rep 6
  { lap_index: 15, distance: 80,  moving_time: 66 },  // recovery
  { lap_index: 16, distance: 200, moving_time: 31 },  // rep 7
  { lap_index: 17, distance: 65,  moving_time: 58 },  // recovery
  { lap_index: 18, distance: 200, moving_time: 32 },  // rep 8 (last)
  { lap_index: 19, distance: 1609, moving_time: 500 },// cooldown mi
  { lap_index: 20, distance: 719,  moving_time: 219 },// cooldown
];

Deno.test("lapRoles: labels all 8 sub-200m reps as reps, keeps every lap", () => {
  const roles = lapRoles(JUL24_LAPS);
  // Every lap is present, none dropped, joined by lap_index.
  assertEquals(roles.length, JUL24_LAPS.length);
  const byIdx = new Map(roles.map((r) => [r.lap_index, r.role]));
  // The 8 reps — including the sub-200m laps 4, 6 the old formula hid.
  for (const idx of [4, 6, 8, 10, 12, 14, 16, 18]) {
    assertEquals(byIdx.get(idx), "rep", `lap ${idx} should be a rep`);
  }
  assertEquals(roles.filter((r) => r.role === "rep").length, 8);
  // Warmup before the first rep, cooldown after the last.
  assertEquals(byIdx.get(1), "warmup");
  assertEquals(byIdx.get(2), "warmup");
  assertEquals(byIdx.get(19), "cooldown");
  assertEquals(byIdx.get(20), "cooldown");
  // Jogs between reps are recoveries.
  for (const idx of [5, 7, 9, 11, 13, 15, 17]) {
    assertEquals(byIdx.get(idx), "recovery", `lap ${idx} should be recovery`);
  }
});

Deno.test("lapRoles: steady run has no rest laps (no fake reps/recoveries)", () => {
  const steady: LapInput[] = Array.from({ length: 6 }, (_, i) => ({
    lap_index: i + 1, distance: 1609, moving_time: 480, // uniform ~6:00/mi miles
  }));
  const roles = lapRoles(steady);
  assertEquals(roles.length, 6);
  assertEquals(roles.filter((r) => r.role === "recovery").length, 0);
});

// ── derivedLapsFromStream ───────────────────────────────────────────────
import { derivedLapsFromStream } from "./workBouts.ts";

/** Per-second stream with heart rate, from constant-velocity phases. */
function buildStreamHR(phases: Array<{ vel: number; secs: number; hr: number }>) {
  const time: number[] = [], distance: number[] = [], velocity_smooth: number[] = [], heartrate: number[] = [];
  let t = 0, d = 0;
  for (const ph of phases) {
    for (let i = 0; i < ph.secs; i++) {
      time.push(t); distance.push(d); velocity_smooth.push(ph.vel); heartrate.push(ph.hr);
      d += ph.vel; t += 1;
    }
  }
  return { time, distance, velocity_smooth, heartrate };
}

const paceSec = (l: { moving_time: number; distance: number }) =>
  Math.round(l.moving_time / (l.distance / 1609.34));

Deno.test("derivedLapsFromStream: recovers 3×1mi reps @ ~5:10 with jog recoveries (Garmin/no native laps)", () => {
  // 3 mile reps @ 5.19 m/s (≈5:10/mi) with 90s jog recoveries @ 1.0 m/s.
  const stream = buildStreamHR([
    { vel: 5.19, secs: 310, hr: 163 },
    { vel: 1.0, secs: 90, hr: 145 },
    { vel: 5.19, secs: 310, hr: 168 },
    { vel: 1.0, secs: 90, hr: 146 },
    { vel: 5.0, secs: 320, hr: 170 },
  ]);
  const laps = derivedLapsFromStream(stream);

  const work = laps.filter((l) => !l.is_rest);
  const rest = laps.filter((l) => l.is_rest);
  assertEquals(work.length, 3, "three work reps");
  assertEquals(rest.length, 2, "two recoveries between them");

  // Each rep parses to ~5:10–5:22, NOT the ~6:20 whole-workout blend.
  for (const w of work) {
    const p = paceSec(w);
    assert(p >= 300 && p <= 330, `rep pace ${p}s should be ~5:00–5:30, got ${p}`);
    assert(w.average_heartrate != null && w.average_heartrate > 150, "work HR carried");
  }
  // Recoveries are slow and HR-lower.
  for (const r of rest) assert(paceSec(r) > 600, "recovery pace is a slow jog");

  // Aggregate work pace ≈ 5:13 — the number the ladder should show.
  const wm = work.reduce((s, l) => s + l.distance, 0);
  const wt = work.reduce((s, l) => s + l.moving_time, 0);
  const agg = Math.round(wt / (wm / 1609.34));
  assert(agg >= 305 && agg <= 320, `aggregate work pace ${agg}s ≈ 5:13`);
});

Deno.test("derivedLapsFromStream: steady run → one whole-run lap, no phantom reps", () => {
  // A continuous run has no recoveries to blend the pace, so its whole-workout
  // pace already equals its work pace — one lap, not fabricated reps.
  const stream = buildStreamHR([{ vel: 3.5, secs: 1800, hr: 150 }]);
  const laps = derivedLapsFromStream(stream);
  assertEquals(laps.length, 1, "one continuous effort");
  assertEquals(laps[0].is_rest, false);
  assert(laps[0].distance > 6000, "spans the whole run");
});

// ── lapsFromParsedStructure (fix-reps → laps) ───────────────────────────
import { lapsFromParsedStructure } from "./workBouts.ts";

Deno.test("lapsFromParsedStructure: corrected 2×1mi @5:10 structure → work+rest laps", () => {
  const parsed = {
    edited_by_user: true,
    blocks: [
      { role: "warmup", distance_miles: 1.0, duration_s: 480, avg_pace_per_mile: "8:00" },
      { role: "work_rep", distance_miles: 1.0, duration_s: 310, avg_pace_per_mile: "5:10", avg_hr: 165 },
      { role: "recovery", distance_miles: 0.1, duration_s: 90, avg_pace_per_mile: null },
      { role: "work_rep", distance_miles: 1.0, duration_s: 314, avg_pace_per_mile: "5:14", avg_hr: 168 },
      { role: "cooldown", distance_miles: 0.5, duration_s: 240, avg_pace_per_mile: "8:00" },
    ],
  };
  const laps = lapsFromParsedStructure(parsed);
  assertEquals(laps.length, 5);
  // Only the two work_reps are non-rest, at rep pace.
  const work = laps.filter((l) => !l.is_rest);
  assertEquals(work.length, 2);
  assertEquals(work[0].avg_pace_sec_per_mile, 310);
  assertEquals(work[1].avg_pace_sec_per_mile, 314);
  assertEquals(work[0].avg_heart_rate, 165);
  // warmup / recovery / cooldown are all rest hints.
  assertEquals(laps.filter((l) => l.is_rest).length, 3);
});

Deno.test("lapsFromParsedStructure: no blocks → empty (caller keeps existing laps)", () => {
  assertEquals(lapsFromParsedStructure({ blocks: [] }).length, 0);
  assertEquals(lapsFromParsedStructure(null).length, 0);
});

// ── Stopped-watch gaps ──────────────────────────────────────────────────────
// Regression cover for the 2026-08-08 long run: 18.1 mi with 12 watch stops
// totalling 755s read as 7:20/mi instead of its true 6:38/mi, because the
// skipped seconds were silently absorbed into the work bout's clock span.

/**
 * Like buildStream, but a phase may be a STOP: the watch is off, so no samples
 * are recorded and the clock jumps forward with the distance standing still —
 * exactly the shape Strava returns for a paused recording.
 */
function buildStreamWithStops(
  phases: Array<{ vel: number; secs: number } | { stopSecs: number }>,
): RawStreams {
  const time: number[] = [];
  const distance: number[] = [];
  const velocity_smooth: number[] = [];
  let t = 0;
  let d = 0;
  for (const ph of phases) {
    if ("stopSecs" in ph) { t += ph.stopSecs; continue; } // no samples emitted
    for (let i = 0; i < ph.secs; i++) {
      time.push(t);
      distance.push(d);
      velocity_smooth.push(ph.vel);
      d += ph.vel;
      t += 1;
    }
  }
  return { time, distance, velocity_smooth };
}

Deno.test("workBouts: a stopped watch mid-run does not slow the bout's pace", () => {
  // 20 minutes at 4.02 m/s (≈6:40/mi), split by a 300s stop at a traffic light.
  const half = { vel: 4.02, secs: 600 };
  const clean = detectWorkBouts(buildStreamWithStops([half, half]));
  const stopped = detectWorkBouts(buildStreamWithStops([half, { stopSecs: 300 }, half]));

  const c = works(clean.segments);
  const s = works(stopped.segments);
  assertEquals(c.length, 1, "continuous run is one bout");
  assertEquals(s.length, 1, "a STOP is not a recovery — the run is still one bout");

  // The stop must not appear as running time…
  assertEquals(s[0].duration_s, c[0].duration_s, "stopped seconds must not count as moving time");
  // …and the pace must be identical to the same run without the stop.
  assertEquals(s[0].avg_pace_per_mile, c[0].avg_pace_per_mile);
  // …but the stop is still reported, not hidden.
  assert(s[0].stopped_s >= 295 && s[0].stopped_s <= 305, `stopped_s was ${s[0].stopped_s}`);
  assertEquals(c[0].stopped_s, 0, "a clean recording reports no stopped time");
});

Deno.test("workBouts: many short stops (the 2026-08-08 long run) keep true pace", () => {
  // Twelve 63s stops sprinkled through a ~6:40/mi run. Pre-fix this read ~7:20.
  const leg = { vel: 4.02, secs: 600 };
  const phases: Array<{ vel: number; secs: number } | { stopSecs: number }> = [];
  for (let i = 0; i < 12; i++) { phases.push(leg, { stopSecs: 63 }); }
  phases.push(leg);
  const w = works(detectWorkBouts(buildStreamWithStops(phases)).segments);
  assertEquals(w.length, 1);
  // 13 × 600s of real running, ±1 sample.
  assert(Math.abs(w[0].duration_s - 7800) <= 13, `duration_s was ${w[0].duration_s}`);
  assertEquals(w[0].avg_pace_per_mile, "6:40");
});

Deno.test("workBouts: a GPS dropout WHILE RUNNING still counts as running time", () => {
  // The mirror case: a tunnel eats 60s of samples but the athlete kept moving,
  // so distance advances across the gap at running speed. That time is real and
  // must NOT be discounted, or the run reads artificially fast.
  const time: number[] = [];
  const distance: number[] = [];
  const velocity_smooth: number[] = [];
  let t = 0, d = 0;
  const runFor = (secs: number) => {
    for (let i = 0; i < secs; i++) {
      time.push(t); distance.push(d); velocity_smooth.push(4.02);
      d += 4.02; t += 1;
    }
  };
  runFor(300);
  t += 60; d += 4.02 * 60; // 60s of missing samples, but the ground was covered
  runFor(300);

  const w = works(detectWorkBouts({ time, distance, velocity_smooth }).segments);
  assertEquals(w.length, 1);
  assert(Math.abs(w[0].duration_s - 660) <= 2, `duration_s was ${w[0].duration_s}`);
  assertEquals(w[0].stopped_s, 0, "a moving dropout is not a stop");
  assertEquals(w[0].avg_pace_per_mile, "6:40");
});

Deno.test("workBouts: a stop cannot masquerade as a recovery that splits reps", () => {
  // Two mile reps with a 90s STOP between them. The watch was off, so there is
  // no recovery to report — but the reps are still separated by it, and neither
  // rep's pace may absorb the stopped time.
  const mile = { vel: 5.0, secs: 322 };
  const { segments } = detectWorkBouts(
    buildStreamWithStops([mile, { stopSecs: 90 }, mile]),
  );
  const w = works(segments);
  assertEquals(w.length, 1, "with no slow samples recorded, the reps read as one effort");
  assertEquals(w[0].duration_s, 643, "only the recorded seconds count");
  assertEquals(w[0].stopped_s, 90);
});

// ── The fabricated blended split (fixed 2026-08-14) ─────────────────────────
//
// THE RULE THESE PROTECT: every split the app shows must be something the
// athlete actually ran. The parser is never allowed to average a rep and its
// jog recovery together and print the blend as one split.
//
// What went wrong: both boundary finders were shown the WHOLE activity —
// warmup and cooldown included. An 8:00/mi warmup is much further from a
// 5:30/mi rep than a 6:15/mi jog recovery is, so the biggest gap in the data is
// warmup-vs-workout, not rep-vs-recovery. The boundary landed below the jog
// recoveries, every rep and recovery classed as "work", and the session came
// back as ONE bout: "7.24 mi @ 5:38/mi" — a distance and a pace that exist
// nowhere in the run. Same session with the warmup and cooldown laps removed
// parsed correctly, which is why it only showed up on real activities.

/** Per-second phase at a M:SS-per-mile pace. */
const atPace = (paceMiles: string, meters: number) => {
  const [m, s] = paceMiles.split(":").map(Number);
  const vel = 1609.34 / (m * 60 + s);
  return { vel, secs: Math.round(meters / vel) };
};

Deno.test("workBouts (GPS): a FULL session — warmup + 6×1mi w/ jog recoveries + cooldown — is not blended into one split", () => {
  const phases = [atPace("7:40", 3218)];
  for (let i = 0; i < 6; i++) {
    phases.push(atPace("5:30", 1609));
    if (i < 5) phases.push(atPace("6:15", 400)); // jog recovery, only ~12% slower
  }
  phases.push(atPace("8:00", 1609));

  const { segments } = detectWorkBouts(buildStream(phases));
  const w = works(segments);
  assertEquals(w.length, 6, "six mile reps — the warmup must not swallow the boundary");
  for (const b of w) {
    assert(
      b.distance_m > 1500 && b.distance_m < 1750,
      `rep ${b.index} = ${b.distance_m}m — a rep+recovery blend would read ~2000m+`,
    );
  }
});

Deno.test("workBouts (GPS): three speed clusters (warmup/cooldown, jog recovery, rep) split at the REP line", () => {
  // Warmup/cooldown ~7:40-8:00, recoveries 7:30, reps 5:30. The two TALLEST
  // clusters here are the easy running and the reps, with the recoveries in
  // between — the old two-tallest-modes rule found no clean valley and gave up,
  // returning the whole 10.24 miles as one "6:25/mi" bout.
  const phases = [atPace("7:40", 3218)];
  for (let i = 0; i < 6; i++) {
    phases.push(atPace("5:30", 1609));
    if (i < 5) phases.push(atPace("7:30", 400));
  }
  phases.push(atPace("8:00", 1609));

  const { segments } = detectWorkBouts(buildStream(phases));
  assertEquals(works(segments).length, 6);
});

Deno.test("workBouts (GPS): a progression WITH a warmup still fabricates no recovery", () => {
  const phases = [
    atPace("8:00", 1609),
    atPace("7:30", 1609),
    atPace("7:00", 1609),
    atPace("6:30", 1609),
    atPace("6:00", 1609),
  ];
  const { segments } = detectWorkBouts(buildStream(phases));
  assertEquals(
    segments.filter((s) => s.kind === "recovery").length,
    0,
    "a run that never alternates must never be cut into reps",
  );
});

// The same real session as MILE_REPEATS_FAST_RECOVERIES, but as the watch
// actually recorded it — with the warmup and cooldown laps that the test
// fixture above omits. Those two laps alone flipped the result.
// An easy warmup and a very easy cooldown are the only difference — and they
// are further from the reps than the jog recoveries are, which is exactly what
// pulled the boundary to the wrong place: the whole session came back as ONE
// bout, "7.49 mi @ 5:44/mi", with 12 of the 15 laps labelled "rep".
const MILE_REPEATS_WITH_WARMUP: LapInput[] = [
  { distance: 3218.68, moving_time: 1140 }, // 2mi warmup (~9:30/mi)
  ...MILE_REPEATS_FAST_RECOVERIES,
  { distance: 1609.34, moving_time: 600 },  // 1mi cooldown (~10:00/mi)
];

Deno.test("boutsFromLaps: warmup + cooldown laps must not blend the reps into one split", () => {
  const { segments } = boutsFromLaps(MILE_REPEATS_WITH_WARMUP);
  const w = lapWorks(segments);
  assertEquals(w.length, 6, "six mile reps, exactly as without the warmup/cooldown laps");
  for (const b of w) {
    assert(b.distance_m > 1500 && b.distance_m < 1700, `rep ${b.index} = ${b.distance_m}m`);
  }
  // The tell-tale symptom: a single multi-mile bout at a pace between rep pace
  // and jog pace.
  assert(
    !w.some((b) => b.distance_m > 3000),
    "no bout may span more than one rep — that would be an invented split",
  );
});

Deno.test("lapRoles: warmup and cooldown are labelled as such, not as reps", () => {
  const roles = lapRoles(
    MILE_REPEATS_WITH_WARMUP.map((l, i) => ({ ...l, lap_index: i })),
  );
  assertEquals(roles.length, MILE_REPEATS_WITH_WARMUP.length);
  assertEquals(roles[0].role, "warmup");
  assertEquals(roles[roles.length - 1].role, "cooldown");
  assertEquals(
    roles.filter((r) => r.role === "rep").length,
    6,
    "exactly the six mile reps — the recoveries are recoveries",
  );
  assertEquals(roles.filter((r) => r.role === "recovery").length, 5);
});

Deno.test("boutsFromLaps: a hilly steady run is never cut into reps", () => {
  // Eight auto-lapped miles, uphill ones a minute slower. Real spread, no
  // alternation — must stay one continuous effort.
  const paces = ["8:00", "8:45", "9:10", "8:20", "7:50", "8:30", "8:55", "8:05"];
  const hilly: LapInput[] = paces.map((p, i) => {
    const [m, s] = p.split(":").map(Number);
    const vel = 1609.34 / (m * 60 + s);
    return { lap_index: i, distance: 1609, moving_time: Math.round(1609 / vel), average_speed: vel };
  });
  assert(workBoutCount(boutsFromLaps(hilly).segments) < 2, "no fabricated rep structure");
  assertEquals(lapRoles(hilly).filter((r) => r.role === "recovery").length, 0);
});

// ── The traffic-light case (fixed 2026-08-14) ──────────────────────────────
//
// Waiting at a light with the watch RUNNING leaves a minute of near-zero
// velocity in the stream, which is indistinguishable from a standing rest
// between two reps. An easy 8-miler came back as "4 reps @ 8:00/mi" — and
// because 4 bouts beat the athlete's own steady mile laps on count, the GPS
// version REPLACED the laps. The laps were right the whole time.
//
// (Actually stopping the watch was never affected: that leaves a time gap, and
// the stop-gap logic discounts it. See the stopped-watch tests above.)

Deno.test("structureHasSpeedContrast: an easy run cut up by standing stops is NOT a workout", () => {
  // Four stretches of the SAME easy pace, separated by standing rests.
  const easy = { vel: 3.35, secs: 600 };
  const light = { vel: 0.05, secs: 60 };
  const { segments } = detectWorkBouts(
    buildStream([easy, light, easy, light, easy, light, easy]),
  );
  assert(workBoutCount(segments) >= 2, "the stream really does segment — that's the trap");
  assertEquals(
    structureHasSpeedContrast(segments, 3.35),
    false,
    "every bout is the run's own pace — there is no workout here",
  );
});

Deno.test("structureHasSpeedContrast: reps with jog recoveries ARE a workout", () => {
  const rep = { vel: 4.85, secs: 330 };
  const jog = { vel: 3.8, secs: 100 };
  const { segments } = detectWorkBouts(
    buildStream([rep, jog, rep, jog, rep, jog, rep]),
  );
  assert(structureHasSpeedContrast(segments, 4.4));
});

Deno.test("structureHasSpeedContrast: standing rests still count when the reps are genuinely fast", () => {
  // A track session the watch auto-lapped by mile: rests are standing, but the
  // reps tower over the run average, so the structure is real.
  const rep = { vel: 5.6, secs: 130 };
  const rest = { vel: 0.1, secs: 90 };
  const warm = { vel: 3.2, secs: 900 };
  const { segments } = detectWorkBouts(
    buildStream([warm, rep, rest, rep, rest, rep, rest, rep, warm]),
  );
  assert(
    structureHasSpeedContrast(segments, 3.6),
    "fast reps against a slow run average — a real session",
  );
});

Deno.test("derivedLapsFromStream: a traffic-light run is one lap, not four fabricated reps", () => {
  const easy = { vel: 3.35, secs: 600, hr: 148 };
  const light = { vel: 0.05, secs: 60, hr: 120 };
  const laps = derivedLapsFromStream(
    buildStreamHR([easy, light, easy, light, easy, light, easy]),
  );
  assertEquals(laps.length, 1, "one continuous run");
  assertEquals(laps[0].is_rest, false);
  assert(laps[0].distance > 7000, "spans the whole run");
});

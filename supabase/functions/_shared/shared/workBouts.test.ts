import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  boutsFromLaps,
  detectWorkBouts,
  formatWorkBouts,
  type LapInput,
  nearestRepDistance,
  nearestTimeRep,
  RawStreams,
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

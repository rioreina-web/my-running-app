import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  bandFor,
  cardiacCost,
  flatEquivalentCost,
  heatIndexF,
  hourDistance,
  hrEffortMultiplier,
  CLIMB_BPM_PER_M_PER_MILE,
  HEAT_OUT_OF_RANGE_F,
  HR_ADJUST_MAX,
  describeRead,
  eligibleForBaseline,
  madSigma,
  median,
  readSession,
  MIN_SAMPLES,
  SIGMA_FLOOR_PCT,
  WINDOW_DAYS,
  type CostSample,
} from "./recoveryRead.ts";

// The athlete this was developed against: easy pace 7:31/mi.
const EASY = 451;

/** n morning sessions at a fixed pace/HR, one per day going back from `fromDay`. */
function historyAt(
  n: number,
  paceSecPerMile: number,
  hrs: number[],
  opts: { hour?: number; minutes?: number; startDay?: number } = {},
): CostSample[] {
  const hour = opts.hour ?? 7;
  const minutes = opts.minutes ?? 45;
  const start = opts.startDay ?? 1;
  return Array.from({ length: n }, (_, i) => {
    const d = new Date(2026, 6, start + i, hour, 0, 0);
    return {
      startedAt: d.toISOString(),
      paceSecPerMile,
      avgHr: hrs[i % hrs.length],
      minutes,
      hoursSinceHard: 48,
    };
  });
}

const at = (day: number, hour: number, pace: number, hr: number, extra: Partial<CostSample> = {}): CostSample => ({
  startedAt: new Date(2026, 6, day, hour, 0, 0).toISOString(),
  paceSecPerMile: pace,
  avgHr: hr,
  minutes: 45,
  hoursSinceHard: 48,
  ...extra,
});

// ── primitives ──────────────────────────────────────────────────────────────

Deno.test("cardiacCost is beats per mile", () => {
  // 7:30/mi at 140 bpm = 7.5 min/mi × 140 = 1050 beats per mile.
  assertEquals(cardiacCost(450, 140), 1050);
  assertEquals(cardiacCost(0, 140), null);
  assertEquals(cardiacCost(450, 0), null);
});

Deno.test("median and madSigma are robust to one outlier", () => {
  assertEquals(median([1, 2, 3, 4, 5]), 3);
  assertEquals(median([1, 2, 3, 4]), 2.5);
  const clean = [100, 101, 102, 103, 104];
  const withOutlier = [...clean, 400];
  // A single blown-up sample must not blow up the band.
  assert(Math.abs(madSigma(clean) - madSigma(withOutlier)) < madSigma(clean) * 0.6);
});

Deno.test("bands travel with the athlete's easy pace", () => {
  assertEquals(bandFor(300, EASY)?.id, "vo2");        // ratio 0.67
  assertEquals(bandFor(350, EASY)?.id, "threshold");  // 0.78
  assertEquals(bandFor(440, EASY)?.id, "moderate");   // 0.98
  assertEquals(bandFor(460, EASY)?.id, "easy");       // 1.02
  // Slower than easy: no band, therefore no read. CV there was 30% in real data.
  assertEquals(bandFor(600, EASY), null);
  // Same absolute pace reads as a HARDER band for a less fit athlete: 7:20/mi
  // against an 8:40 easy pace is marathon-ish work, against a 7:31 easy pace
  // it is just moderate. This is the point of ratio bands.
  assertEquals(bandFor(440, 520)?.id, "marathon");
  assertEquals(bandFor(440, EASY)?.id, "moderate");
  // ...and slower than the fitter athlete's easy pace, so: no band at all.
  assertEquals(bandFor(440, 400), null);
});

Deno.test("eligibleForBaseline rejects short runs and cooldown jogs", () => {
  assert(eligibleForBaseline(at(1, 7, 450, 140), EASY));
  assert(!eligibleForBaseline(at(1, 7, 450, 140, { minutes: 8 }), EASY));
  assert(!eligibleForBaseline(at(1, 7, 450, 140, { hoursSinceHard: 1 }), EASY));
  assert(!eligibleForBaseline(at(1, 7, 700, 140), EASY)); // slower than easy
});

// ── the read: refusals ──────────────────────────────────────────────────────

Deno.test("refuses to read with too few comparable sessions", () => {
  const r = readSession(at(20, 7, 450, 145), historyAt(MIN_SAMPLES - 1, 450, [140]), EASY);
  assertEquals(r.verdict, "no-read");
  assertEquals(r.samplesUsed, MIN_SAMPLES - 1);
  assert(r.blockedBy!.includes("needs"));
  assert(r.cost !== null, "cost is still reported even with no baseline");
});

Deno.test("refuses to read a cooldown jog", () => {
  const r = readSession(at(20, 9, 450, 160, { hoursSinceHard: 1 }), historyAt(20, 450, [140]), EASY);
  assertEquals(r.verdict, "no-read");
  assert(r.blockedBy!.includes("same effort"));
});

Deno.test("refuses to read slower-than-easy running", () => {
  const r = readSession(at(20, 7, 700, 130), historyAt(20, 450, [140]), EASY);
  assertEquals(r.verdict, "no-read");
  assert(r.blockedBy!.includes("slower than easy"));
});

Deno.test("refuses to read a session with no heart rate", () => {
  const r = readSession(at(20, 7, 450, 0), historyAt(20, 450, [140]), EASY);
  assertEquals(r.verdict, "no-read");
  assertEquals(r.cost, null);
});

Deno.test("baseline never sees the future", () => {
  // All history is AFTER the session — so there is nothing to compare against.
  const future = historyAt(20, 450, [140], { startDay: 25 });
  const r = readSession(at(20, 7, 450, 145), future, EASY);
  assertEquals(r.verdict, "no-read");
  assertEquals(r.samplesUsed, 0);
});

Deno.test("baseline is matched on daypart, not corrected for it", () => {
  // 20 evening sessions cannot serve a morning session: measured at 5.4 bpm,
  // time of day was the largest confounder in the real data.
  const evenings = historyAt(20, 450, [140], { hour: 18 });
  const r = readSession(at(25, 7, 450, 145), evenings, EASY);
  assertEquals(r.verdict, "no-read");
  assertEquals(r.samplesUsed, 0);
});

Deno.test("stale samples fall out of the window", () => {
  const old = historyAt(20, 450, [140], { startDay: 1 });
  // 60 days later — everything is outside WINDOW_DAYS.
  const r = readSession(at(1 + WINDOW_DAYS + 20, 7, 450, 145), old, EASY);
  assertEquals(r.verdict, "no-read");
});

// ── the read: verdicts ──────────────────────────────────────────────────────

Deno.test("ordinary variation reads as nothing detected, not as recovery", () => {
  const hist = historyAt(20, 450, [138, 140, 142, 139, 141]);
  const r = readSession(at(25, 7, 450, 141, { elevationGainMetersPerMile: 5 }), hist, EASY);
  assertEquals(r.verdict, "nothing-detected");
  assertEquals(r.confidence, "high");
  assert(describeRead(r).includes("Within your normal spread"));
});

Deno.test("a large excursion is surfaced", () => {
  const hist = historyAt(20, 450, [138, 140, 142, 139, 141]);
  const r = readSession(at(25, 7, 450, 155), hist, EASY); // ~+10% cost
  assertEquals(r.verdict, "very-elevated");
  assert(r.z! > 2.5);
  assert(r.deltaPct! > 8);
  assert(describeRead(r).includes("more beats per mile"));
});

Deno.test("an unusually cheap session is surfaced too", () => {
  const hist = historyAt(20, 450, [138, 140, 142, 139, 141]);
  const r = readSession(at(25, 7, 450, 125), hist, EASY);
  assertEquals(r.verdict, "lower-than-usual");
  assert(describeRead(r).includes("fewer beats per mile"));
});

Deno.test("self-calibrating: the same +6 bpm is signal for a tight athlete and noise for a variable one", () => {
  const session = at(25, 7, 450, 146);
  const tight = readSession(session, historyAt(20, 450, [139, 140, 141]), EASY);
  const variable = readSession(session, historyAt(20, 450, [130, 136, 140, 144, 150]), EASY);
  assertEquals(tight.verdict, "very-elevated");
  assertEquals(variable.verdict, "nothing-detected");
  assert(variable.sigma! > tight.sigma!);
});

Deno.test("sigma floor stops a freakishly tight window from crying wolf", () => {
  // Every session identical → MAD is 0. Without the floor, z would be infinite.
  const hist = historyAt(20, 450, [140]);
  const r = readSession(at(25, 7, 450, 141), hist, EASY);
  assertEquals(r.sigma, Math.round(r.baseline! * SIGMA_FLOOR_PCT * 10) / 10);
  assert(isFinite(r.z!));
  assertEquals(r.verdict, "nothing-detected");
});

Deno.test("a faster session is compared to its own band, not to easy running", () => {
  const easyHist = historyAt(20, 450, [140]);
  const thHist = historyAt(20, 350, [168], { startDay: 1 });
  // A threshold session with only easy history behind it gets no read...
  assertEquals(readSession(at(25, 7, 350, 170), easyHist, EASY).verdict, "no-read");
  // ...but with threshold history it reads normally.
  const r = readSession(at(25, 7, 350, 169), thHist, EASY);
  assertEquals(r.bandId, "threshold");
  assertEquals(r.verdict, "nothing-detected");
});

// ── climb correction ────────────────────────────────────────────────────────

Deno.test("flatEquivalentCost pays back the hill", () => {
  const flat = { startedAt: new Date(2026, 6, 1, 7).toISOString(), paceSecPerMile: 450, avgHr: 140, minutes: 45 };
  // 10 m/mile of climb is worth 3.16 bpm, so the flat-equivalent HR is 136.84.
  const hilly = { ...flat, elevationGainMetersPerMile: 10 };
  assertEquals(flatEquivalentCost(flat), 1050);
  assertEquals(Math.round(flatEquivalentCost(hilly)! * 100) / 100, Math.round(7.5 * (140 - 10 * CLIMB_BPM_PER_M_PER_MILE) * 100) / 100);
  assert(flatEquivalentCost(hilly)! < flatEquivalentCost(flat)!);
  // Missing elevation is not a refusal — it falls back to the raw cost.
  assertEquals(flatEquivalentCost({ ...flat, elevationGainMetersPerMile: null }), 1050);
});

Deno.test("a hilly run is not mistaken for fatigue", () => {
  // Baseline: flat morning easy runs at 140 bpm.
  const flatHist = historyAt(20, 450, [139, 140, 141]).map((h) => ({ ...h, elevationGainMetersPerMile: 2 }));
  // Today: same pace, HR 146 — but 20 m/mile of climb explains ~6.3 of it.
  const hilly = at(25, 7, 450, 146, { elevationGainMetersPerMile: 20 });
  const uncorrected = at(25, 7, 450, 146, { elevationGainMetersPerMile: 2 });
  assertEquals(readSession(hilly, flatHist, EASY).verdict, "nothing-detected");
  assertEquals(readSession(uncorrected, flatHist, EASY).verdict, "very-elevated");
});

Deno.test("unknown climb downgrades confidence rather than blocking", () => {
  const hist = historyAt(20, 450, [139, 140, 141]);
  const r = readSession(at(25, 7, 450, 141), hist, EASY);
  assertEquals(r.verdict, "nothing-detected");
  assertEquals(r.confidence, "low");
});

// ── conditions guard ────────────────────────────────────────────────────────

Deno.test("heatIndexF is sane at both ends of the Rothfusz split", () => {
  // Cool and dry reads close to the air temperature.
  const cool = heatIndexF(60, 45)!;
  assert(Math.abs(cool - 60) < 6, `cool=${cool}`);
  // Hot and humid reads well above it.
  const hot = heatIndexF(95, 75)!;
  assert(hot > 100, `hot=${hot}`);
  // Same temperature, drier air, lower apparent temperature.
  assert(heatIndexF(95, 60)! < hot);
  assertEquals(heatIndexF(NaN, 70), null);
});

Deno.test("ordinary weather variation does NOT trip the guard", () => {
  // Baseline around 80F apparent; today 6F warmer — the real within-window spread.
  const hist = historyAt(20, 450, [139, 140, 141]).map((h) => ({
    ...h, elevationGainMetersPerMile: 5, heatIndexF: 80,
  }));
  const r = readSession(
    at(25, 7, 450, 141, { elevationGainMetersPerMile: 5, heatIndexF: 86 }), hist, EASY);
  assertEquals(r.verdict, "nothing-detected");
});

Deno.test("a race in far hotter conditions gets no read, not a fatigue verdict", () => {
  const hist = historyAt(20, 450, [139, 140, 141]).map((h) => ({
    ...h, elevationGainMetersPerMile: 5, heatIndexF: 78,
  }));
  const away = at(25, 7, 450, 152, {
    elevationGainMetersPerMile: 5, heatIndexF: 78 + HEAT_OUT_OF_RANGE_F + 8,
  });
  const r = readSession(away, hist, EASY);
  assertEquals(r.verdict, "no-read");
  assert(r.blockedBy!.includes("conditions too different"));
  // The cost is still reported — we measured it, we just will not interpret it.
  assert(r.cost !== null);
  // 7:30/mi against a 7:31 easy anchor is ratio 0.998 — the moderate band.
  assertEquals(r.bandId, "moderate");
});

Deno.test("an athlete with genuinely variable conditions is not blocked constantly", () => {
  // Baseline spans a wide range of apparent temperature.
  const wide = historyAt(20, 450, [139, 140, 141]).map((h, i) => ({
    ...h, elevationGainMetersPerMile: 5, heatIndexF: 60 + (i % 5) * 12,
  }));
  const r = readSession(
    at(25, 7, 450, 141, { elevationGainMetersPerMile: 5, heatIndexF: 100 }), wide, EASY);
  assertEquals(r.verdict, "nothing-detected");
});

Deno.test("no weather data simply skips the guard", () => {
  const hist = historyAt(20, 450, [139, 140, 141]).map((h) => ({
    ...h, elevationGainMetersPerMile: 5,
  }));
  const r = readSession(at(25, 7, 450, 141, { elevationGainMetersPerMile: 5 }), hist, EASY);
  assertEquals(r.verdict, "nothing-detected");
});

// ── load adjustment ─────────────────────────────────────────────────────────

Deno.test("hourDistance is circular", () => {
  assertEquals(hourDistance(23.5, 0.5), 1);
  assertEquals(hourDistance(6, 18), 12);
  assertEquals(hourDistance(12, 12), 0);
});

Deno.test("daypart matching is hour-proximity, not a fixed cutoff", () => {
  // History at 10:00, session at 12:30 — 2.5h apart, same daypart under
  // proximity matching even though a fixed 11:00 line would split them.
  const hist = historyAt(20, 450, [139, 140, 141], { hour: 10 }).map((h) => ({
    ...h, elevationGainMetersPerMile: 5,
  }));
  const r = readSession(
    { ...at(25, 12, 450, 141, { elevationGainMetersPerMile: 5 }),
      startedAt: new Date(2026, 6, 25, 12, 30).toISOString() }, hist, EASY);
  assertEquals(r.verdict, "nothing-detected");
});

Deno.test("hrEffortMultiplier: no read means exactly 1.0", () => {
  const r = readSession(at(20, 7, 450, 0), historyAt(20, 450, [140]), EASY);
  assertEquals(hrEffortMultiplier(r), 1);
});

Deno.test("hrEffortMultiplier half-credits a real excursion and caps a spike", () => {
  const hist = historyAt(20, 450, [138, 140, 142, 139, 141]).map((h) => ({
    ...h, elevationGainMetersPerMile: 5,
  }));
  // ~+7% cost → ~+2.9% load, well inside the cap.
  const up = readSession(at(25, 7, 450, 150, { elevationGainMetersPerMile: 5 }), hist, EASY);
  const mUp = hrEffortMultiplier(up);
  assert(mUp > 1.02 && mUp < 1.04, `mUp=${mUp}`);
  // A strap-dropout-sized +40% cost is capped, never doubled.
  const spike = readSession(at(25, 7, 450, 196, { elevationGainMetersPerMile: 5 }), hist, EASY);
  assertEquals(hrEffortMultiplier(spike), 1 + HR_ADJUST_MAX);
  // An unusually cheap session discounts, symmetrically bounded.
  const down = readSession(at(25, 7, 450, 130, { elevationGainMetersPerMile: 5 }), hist, EASY);
  const mDown = hrEffortMultiplier(down);
  assert(mDown < 1 && mDown >= 1 - HR_ADJUST_MAX, `mDown=${mDown}`);
});

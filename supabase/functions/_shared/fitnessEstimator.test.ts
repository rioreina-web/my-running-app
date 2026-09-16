import { assert, assertAlmostEquals, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  COLD_START_SD,
  estimateFitness,
  MAX_STATE_SD,
  type Observation,
  PROCESS_SD_PER_WEEK,
  efficiencyObservation,
  raceObservation,
  sessionObservation,
} from "./fitnessEstimator.ts";

const NOW = new Date("2026-07-02T12:00:00Z");
const day = (agoDays: number) => new Date(NOW.getTime() - agoDays * 86_400_000).toISOString().slice(0, 10);

const race = (pace: number, agoDays: number, sd = 0.006): Observation =>
  ({ date: day(agoDays), kind: "race", pace, sd, why: "race" });
const session = (pace: number, agoDays: number, sd = 0.02): Observation =>
  ({ date: day(agoDays), kind: "session", pace, sd, why: "session" });

const run = (obs: Observation[], load?: Parameters<typeof estimateFitness>[0]["load"]) =>
  estimateFitness({ observations: obs, now: NOW, load });

// ── abstention ──────────────────────────────────────────────────────────────

Deno.test("no evidence yields null, never a fabricated number", () => {
  assertEquals(run([]), null);
});

Deno.test("malformed observations are skipped, not fatal", () => {
  const r = run([
    { date: "not-a-date", kind: "session", pace: 310, sd: 0.02, why: "" },
    { date: day(3), kind: "session", pace: NaN, sd: 0.02, why: "" },
    { date: day(3), kind: "session", pace: 310, sd: 0, why: "" },
    session(310, 2),
  ]);
  assert(r !== null);
  assertEquals(r!.observationCount, 1);
});

// ── the acceptance cases harvested from evidenceBlend.ts ────────────────────

Deno.test("ACCEPTANCE — eight weeks of training closes >80% of the race→training gap", () => {
  // The case the whole redesign exists for. A race eight weeks ago says 330;
  // sixteen sessions since, all saying 315. By now the estimate must have
  // followed the training, not stayed pinned to the race.
  const obs = [race(330, 56)];
  for (let w = 0; w < 8; w++) {
    obs.push(session(315, w * 7 + 2), session(315, w * 7 + 5));
  }
  const r = run(obs)!;
  const closed = (330 - r.pace) / (330 - 315);
  assert(closed > 0.8, `expected >80% of the gap closed, got ${(closed * 100).toFixed(0)}% (${r.pace.toFixed(1)})`);
});

Deno.test("a race run yesterday dominates the sessions around it", () => {
  const r = run([race(310, 1), session(330, 3), session(330, 6)])!;
  assert(r.pace < 316, `a fresh race should hold the estimate near itself; got ${r.pace.toFixed(1)}`);
  // ...and the gain on that race should be the largest of the three.
  const raceStep = r.steps.find((s) => s.kind === "race")!;
  assert(raceStep.gain > 0.5, `fresh race gain was only ${raceStep.gain.toFixed(2)}`);
});

Deno.test("an old race fades rather than anchoring forever", () => {
  const fresh = run([race(300, 7), session(330, 3)])!.pace;
  const stale = run([race(300, 300), session(330, 3)])!.pace;
  assert(stale > fresh, `a 300-day-old race must hold less: ${stale.toFixed(1)} vs ${fresh.toFixed(1)}`);
});

Deno.test("there is no ceiling — sustained training can move any distance", () => {
  // 12% faster than a year-old race. No cap may stand in the way.
  const obs = [race(360, 365)];
  for (let w = 0; w < 12; w++) obs.push(session(317, w * 7 + 2));
  const r = run(obs)!;
  assert(r.pace < 320, `training must reach its own level uncapped; got ${r.pace.toFixed(1)}`);
});

Deno.test("the estimate follows form DOWN as readily as up", () => {
  const obs = [race(300, 70)];
  for (let w = 0; w < 8; w++) obs.push(session(330, w * 7 + 2));
  const r = run(obs)!;
  assert(r.pace > 325, `a block of slower work must be believed too; got ${r.pace.toFixed(1)}`);
});

Deno.test("recency ordering holds within a kind", () => {
  const recentFast = run([session(300, 2), session(320, 60)])!.pace;
  const recentSlow = run([session(320, 2), session(300, 60)])!.pace;
  assert(recentFast < recentSlow, "whichever is newer should pull harder");
});

Deno.test("training alone works, and a race alone works", () => {
  assert(run([session(315, 3)]) !== null);
  assert(run([race(315, 3)]) !== null);
});

// ── what replaces the clamps ────────────────────────────────────────────────

Deno.test("weak evidence moves the number less — the cap, as an outcome", () => {
  // Identical claim, different confidence. No rule says "training may move the
  // estimate at most 2%"; the variance says how far it gets.
  const strong = run([race(320, 30), session(300, 1, 0.008)])!.pace;
  const weak = run([race(320, 30), session(300, 1, 0.06)])!.pace;
  assert(strong < weak, `strong evidence must move further: ${strong.toFixed(1)} vs ${weak.toFixed(1)}`);
  assert(weak > 315, `thin evidence should barely move it; got ${weak.toFixed(1)}`);
});

Deno.test("uncertainty grows with silence, so the next session counts for more", () => {
  const soon = run([race(320, 30), session(300, 29)])!;
  const late = run([race(320, 200), session(300, 1)])!;
  const soonGain = soon.steps.find((s) => s.kind === "session")!.gain;
  const lateGain = late.steps.find((s) => s.kind === "session")!.gain;
  assert(lateGain > soonGain, `a wider prior must believe more: ${lateGain.toFixed(2)} vs ${soonGain.toFixed(2)}`);
});

Deno.test("the state does not drift on its own — only its variance grows", () => {
  // The direct fix for "pinned to the last race": with no load information and
  // no new evidence, the estimate holds and the RANGE widens. It must not
  // invent a decline it has no evidence for.
  const r = run([race(320, 180)])!;
  assertAlmostEquals(r.pace, 320, 0.01);
  assert(r.sd > 0.02, `six months of silence should widen the range; got ${(r.sd * 100).toFixed(1)}%`);
});

Deno.test("sustained load collapse DOES drift the estimate slower", () => {
  // The one deterministic term: absence of training is itself evidence.
  const load = Array.from({ length: 180 }, (_, i) => ({ date: day(180 - i), relativeLoad: 0.05 }));
  const detrained = run([race(320, 180)], load)!;
  const held = run([race(320, 180)], Array.from({ length: 180 }, (_, i) => ({ date: day(180 - i), relativeLoad: 1.0 })))!;
  assert(detrained.pace > 325, `six months off must cost something; got ${detrained.pace.toFixed(1)}`);
  assertAlmostEquals(held.pace, 320, 0.01);
});

Deno.test("posterior SD is bounded — a layoff cannot make one session gospel", () => {
  const r = run([race(320, 2000)])!;
  assert(r.sd <= MAX_STATE_SD + 1e-9, `sd ran away to ${r.sd}`);
});

Deno.test("cold start is a wide prior, not a separate code path", () => {
  const r = run([session(315, 1)])!;
  // One session against a 12% prior lands most of the way onto that session...
  assert(Math.abs(r.pace - 315) < 3, `got ${r.pace.toFixed(1)}`);
  // ...but says loudly that it is one session.
  assert(r.sd > 0.015, `a single-session estimate must stay wide; got ${(r.sd * 100).toFixed(1)}%`);
  assert(COLD_START_SD > PROCESS_SD_PER_WEEK * 4, "the prior must be wider than a month of drift");
});

Deno.test("a supplied prior seeds the recursion instead of the cold start", () => {
  const seeded = estimateFitness({
    observations: [session(300, 1)],
    now: NOW,
    prior: { pace: 340, sd: 0.01, date: day(10) },
  })!;
  assert(seeded.pace > 320, `a tight prior must resist one session; got ${seeded.pace.toFixed(1)}`);
});

Deno.test("observations are applied oldest-first regardless of input order", () => {
  const forward = run([session(320, 40), session(300, 2)])!.pace;
  const shuffled = run([session(300, 2), session(320, 40)])!.pace;
  assertAlmostEquals(forward, shuffled, 1e-9);
});

// ── the observation builders ────────────────────────────────────────────────

Deno.test("a heavily-corrected race is admitted, but weighed less", () => {
  const ideal = raceObservation(1880, 0, "2026-02-07", "10K");
  const hot = raceObservation(1880, 0.04, "2026-04-12", "10K");
  assert(hot.sd > ideal.sd * 2, `correction must cost weight: ${hot.sd} vs ${ideal.sd}`);
  // ...and is NOT excluded, which is what SHAPE_MAX_CORRECTION_PCT used to do.
  assert(hot.pace === 1880);
});

Deno.test("session variance widens with thin work, low confidence and distance off-curve", () => {
  const solid = sessionObservation(310, 40, 1.0, 0.9, day(1), "s");
  const thin = sessionObservation(310, 8, 1.0, 0.9, day(1), "s");
  const unsure = sessionObservation(310, 40, 1.0, 0.3, day(1), "s");
  const offCurve = sessionObservation(310, 40, 1.08, 0.9, day(1), "s");
  assert(thin.sd > solid.sd, "8 minutes says less than 40");
  assert(unsure.sd > solid.sd, "parser doubt is uncertainty about the geometry");
  assert(offCurve.sd > solid.sd, "far off the curve is more likely a mis-parse");
});

Deno.test("a race outweighs a session of equal age, without a kind rule", () => {
  // evidenceBlend needed RACE_WEIGHT = 3. Here it falls out of the variances.
  const r = raceObservation(1880, 0, day(1), "10K");
  const s = sessionObservation(1880 / 6.214, 25, 1.0, 0.8, day(1), "s");
  assert(r.sd < s.sd, `a race should be the tighter observation: ${r.sd} vs ${s.sd}`);
});

// ── EF as drift evidence (§12) ──────────────────────────────────────────────

Deno.test("EF drift becomes a level observation off the baseline state", () => {
  const o = efficiencyObservation(320, -6, 4, 10, 12, day(1), "EF")!;
  assert(o !== null);
  assertEquals(o.kind, "efficiency");
  assertAlmostEquals(o.pace, 314, 1e-9, "baseline level plus the drift");
});

Deno.test("EF is admitted in BOTH directions, unlike the shipped one-way gate", () => {
  const faster = efficiencyObservation(320, -6, 4, 10, 12, day(1), "EF")!;
  const slower = efficiencyObservation(320, +6, 4, 10, 12, day(1), "EF")!;
  assert(faster.pace < 320 && slower.pace > 320);
});

Deno.test("a thin EF trend is admitted but weighed like a thin thing", () => {
  const thin = efficiencyObservation(320, -6, 4, 3, 3, day(1), "EF")!;
  const solid = efficiencyObservation(320, -6, 4, 20, 30, day(1), "EF")!;
  assert(thin.sd > solid.sd, `${thin.sd} vs ${solid.sd}`);
});

Deno.test("EF is weaker evidence than a session, which is weaker than a race", () => {
  // Cheaper-per-beat is consistent with fitter, and also with cooler, fresher
  // and better rested. The ordering must survive.
  const ef = efficiencyObservation(320, -6, 4, 20, 30, day(1), "EF")!;
  const s = sessionObservation(320, 25, 1.0, 0.8, day(1), "s");
  const r = raceObservation(1880, 0, day(1), "10K");
  assert(r.sd < s.sd && s.sd < ef.sd, `race ${r.sd} < session ${s.sd} < EF ${ef.sd}`);
});

Deno.test("too few reps on either side yields nothing, not a guess", () => {
  assertEquals(efficiencyObservation(320, -6, 4, 2, 30, day(1), "EF"), null);
  assertEquals(efficiencyObservation(320, -6, 4, 30, 2, day(1), "EF"), null);
});

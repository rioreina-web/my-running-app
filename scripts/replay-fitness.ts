#!/usr/bin/env -S deno run --allow-net --allow-env
/**
 * replay-fitness.ts — score the fitness predictor against history.
 *
 * WHY (G0.1 in FITNESS-SCALE-APPLY.md). The predictor has shipped for five
 * months and `prediction_scores` holds exactly one row, written by the retired
 * device model. Every constant in `fitnessPrediction.ts` is defended by an
 * argument in a comment and by nothing else. This makes each of them a
 * measurement instead.
 *
 * WHAT IT DOES. Walks a date range forward one step at a time, and at each
 * step assembles the inputs THAT EXISTED AT THAT MOMENT, runs the real
 * `generateFitnessPrediction`, and feeds the result into the next step as the
 * curve's prior. Then it scores each race against the prediction standing some
 * number of days before it.
 *
 * THE THREE RULES IT HAS TO FOLLOW, and where each lives:
 *
 *   1. Point-in-time by `created_at`, never `workout_date` — in
 *      `_shared/fitnessInputs.ts` (`asOf`), so production and replay share one
 *      assembly. A replay with its own fetch is measuring a sibling model.
 *   2. The replay feeds its OWN chain, not the stored snapshots.
 *      `smoothFitnessPace` makes the model path-dependent: a one-shot
 *      prediction at D is a different estimator than the one that ships. See
 *      `chain` below.
 *   3. `diagnostics` is kept per step. A backtest that stores only the output
 *      tells you THAT it was wrong, not WHICH STAGE was.
 *
 * WHAT IT CANNOT DO — read the limits in `fitnessInputs.ts`'s header before
 * trusting a number. Briefly: `parsed_structure` has no per-column history so
 * the row's `created_at` is an optimistic proxy, and `athlete_state
 * .fitness_signal` has no history at all, so the EF gate is OFF in replay
 * (which is its documented no-evidence path, not a hack). Sub-1% replay
 * differences are noise from these two, not signal.
 *
 * USAGE
 *   SUPABASE_URL=https://<ref>.supabase.co \
 *   SUPABASE_SERVICE_ROLE_KEY=eyJ... \
 *   deno run --allow-net --allow-env scripts/replay-fitness.ts --user=<uuid>
 *
 *   --user=<uuid>        required
 *   --from=YYYY-MM-DD    chain start (default: 200d before the first race)
 *   --to=YYYY-MM-DD      chain end   (default: today)
 *   --step=N             days per step (default 1 — the nightly cron's cadence)
 *   --horizons=1,7,14,28 days before race day to score at (default 1,7,14,28,56)
 *   --json               emit the full chain as JSON instead of the tables
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { generateFitnessPrediction, type FitnessPredictionResult, type PriorSnapshotInput }
  from "../supabase/functions/_shared/fitnessPrediction.ts";
import { buildPredictionInput, distanceToRaceType } from "../supabase/functions/_shared/fitnessInputs.ts";

// ---------------------------------------------------------------------------

const args = new Map<string, string>();
for (const a of Deno.args) {
  const m = a.match(/^--([^=]+)(?:=(.*))?$/);
  if (m) args.set(m[1], m[2] ?? "true");
}
const userId = args.get("user");
if (!userId) {
  console.error("required: --user=<uuid>");
  Deno.exit(1);
}
const stepDays = Number(args.get("step") ?? 1);
const horizons = (args.get("horizons") ?? "1,7,14,28,56").split(",").map(Number).filter((n) => n > 0);

const url = Deno.env.get("SUPABASE_URL");
const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!url || !key) {
  console.error("required env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY");
  Deno.exit(1);
}
const db = createClient(url, key);

const DAY = 86_400_000;
const day = (d: Date) => d.toISOString().slice(0, 10);
const parseDay = (s: string) => new Date(`${s}T00:00:00.000Z`);
const fmt = (s: number | null | undefined) => {
  if (s == null || !Number.isFinite(s)) return "—";
  const t = Math.round(s), h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), x = t % 60;
  return h > 0
    ? `${h}:${String(m).padStart(2, "0")}:${String(x).padStart(2, "0")}`
    : `${m}:${String(x).padStart(2, "0")}`;
};
const pad = (s: string, n: number) => s.padEnd(n);
const padS = (s: string, n: number) => s.padStart(n);

// ---------------------------------------------------------------------------
// The races we score against.
// ---------------------------------------------------------------------------

interface Race {
  date: string;
  distanceKey: string;
  actualSeconds: number;
  logId: string;
}

const { data: raceRows, error: raceErr } = await db
  .from("training_logs")
  .select("id, workout_date, race_result")
  .eq("user_id", userId)
  .not("race_result", "is", null)
  .order("workout_date", { ascending: true })
  .limit(200);
if (raceErr) {
  console.error(`race fetch: ${raceErr.message}`);
  Deno.exit(1);
}

const races: Race[] = [];
for (const r of raceRows ?? []) {
  const rr = r.race_result as { distance?: string; finish_time_seconds?: number } | null;
  const d = String(r.workout_date ?? "").slice(0, 10);
  if (!rr || typeof rr.finish_time_seconds !== "number" || !d) continue;
  if (!distanceToRaceType(String(rr.distance ?? ""))) continue;
  races.push({ date: d, distanceKey: String(rr.distance), actualSeconds: rr.finish_time_seconds, logId: String(r.id) });
}
if (races.length === 0) {
  console.error("no scoreable races for this athlete");
  Deno.exit(1);
}

const defaultFrom = day(new Date(parseDay(races[0].date).getTime() - 200 * DAY));
const from = parseDay(args.get("from") ?? defaultFrom);
const to = parseDay(args.get("to") ?? day(new Date()));

// ---------------------------------------------------------------------------
// The chain. Each step's prediction becomes the next step's curve prior — the
// production writer keeps one row per UTC day, so the chain does too.
// ---------------------------------------------------------------------------

interface Step {
  date: string;
  pred: FitnessPredictionResult | null;
  logRows: number;
  laps: number;
}

const chain: PriorSnapshotInput[] = [];
const steps: Step[] = [];

const totalSteps = Math.floor((to.getTime() - from.getTime()) / (stepDays * DAY)) + 1;
console.error(
  `replaying ${totalSteps} steps · ${day(from)} → ${day(to)} · step ${stepDays}d · ${races.length} races\n`,
);

let done = 0;
for (let t = from.getTime(); t <= to.getTime(); t += stepDays * DAY) {
  // 03:30 UTC — the nightly cron's hour. `asOf` is this instant, so a row
  // created later the same day is correctly invisible.
  const at = new Date(t);
  at.setUTCHours(3, 30, 0, 0);

  const { input, provenance } = await buildPredictionInput(db, userId, at, {
    asOf: at,
    // Rule 2: our own chain, never the stored rows.
    priorSnapshots: chain.slice(0, 50),
    // No history on athlete_state — see fitnessInputs.ts class 3.
    includeEfficiencySignal: false,
  });

  const pred = generateFitnessPrediction(input);
  steps.push({ date: day(at), pred, logRows: provenance.logRowCount, laps: provenance.lapRowCount });

  if (pred) {
    chain.unshift({
      createdAt: at.toISOString(),
      estimated10kPaceSeconds: pred.estimated10kPaceSeconds,
      confidence: pred.confidence,
      dataSource: pred.dataSource, // carries "· v2" → isOwnSnapshot sees it
    });
  }

  done++;
  if (done % 20 === 0) console.error(`  ${done}/${totalSteps} · ${day(at)} · ${pred ? fmt(pred.predicted10kSeconds) : "null"}`);
}

if (args.get("json")) {
  console.log(JSON.stringify({ steps, races }, null, 2));
  Deno.exit(0);
}

// ---------------------------------------------------------------------------
// Scoring.
// ---------------------------------------------------------------------------

const predictedFor = (p: FitnessPredictionResult, distanceKey: string): number | null => {
  switch (distanceKey.toLowerCase()) {
    case "mile": return p.predictedMileSeconds;
    case "5k": return p.predicted5kSeconds;
    case "10k": return p.predicted10kSeconds;
    case "half": return p.predictedHalfSeconds;
    case "marathon": return p.predictedMarathonSeconds;
    default: return null;
  }
};

/** Last step strictly before `target`. Mirrors prediction_scores' rule. */
const stepBefore = (target: Date): Step | null => {
  let best: Step | null = null;
  for (const s of steps) {
    if (parseDay(s.date).getTime() < target.getTime() && s.pred) best = s;
  }
  return best;
};

console.log(`\n${"═".repeat(78)}`);
console.log(`REPLAY SCORES · ${races.length} races · EF gate OFF (no history) · step ${stepDays}d`);
console.log("═".repeat(78));

interface Row { race: string; horizon: number; lagDays: number; predicted: number; actual: number; errPct: number }
const rows: Row[] = [];

for (const race of races) {
  const raceDay = parseDay(race.date);
  console.log(`\n${race.date} · ${race.distanceKey.toUpperCase()} · actual ${fmt(race.actualSeconds)}`);
  console.log(`  ${pad("target", 9)}${pad("actual lag", 11)}${padS("predicted", 10)}${padS("error", 9)}${padS("error %", 9)}  source`);
  for (const h of horizons) {
    const s = stepBefore(new Date(raceDay.getTime() - (h - 1) * DAY));
    if (!s?.pred) {
      console.log(`  ${pad(`-${h}d`, 9)}${pad("—", 11)}${padS("—", 10)}${padS("—", 9)}${padS("—", 9)}  no prediction yet`);
      continue;
    }
    // The step grid rarely lands exactly on the requested horizon. Report the
    // lag that was actually used — a label that rounds a 9-day-old prediction
    // to "-7d" is the kind of small dishonesty this harness exists to remove.
    const lagDays = Math.round((raceDay.getTime() - parseDay(s.date).getTime()) / DAY);
    const predicted = predictedFor(s.pred, race.distanceKey);
    if (predicted == null) continue;
    const err = predicted - race.actualSeconds;
    const errPct = (err / race.actualSeconds) * 100;
    rows.push({ race: `${race.date} ${race.distanceKey}`, horizon: h, lagDays, predicted, actual: race.actualSeconds, errPct });
    console.log(
      `  ${pad(`-${h}d`, 9)}${pad(`${lagDays}d before`, 11)}${padS(fmt(predicted), 10)}${padS(`${err > 0 ? "+" : ""}${Math.round(err)}s`, 9)}` +
      `${padS(`${errPct > 0 ? "+" : ""}${errPct.toFixed(2)}%`, 9)}  ${s.pred.dataSource}`,
    );
  }
}

console.log(`\n${"─".repeat(78)}`);
console.log("BY HORIZON  (error > 0 = model predicted SLOWER than the athlete ran)");
console.log("─".repeat(78));
console.log(`  ${pad("horizon", 10)}${padS("n", 4)}${padS("mean err%", 12)}${padS("MAPE", 10)}${padS("worst", 10)}`);
for (const h of horizons) {
  const hs = rows.filter((r) => r.horizon === h);
  if (hs.length === 0) continue;
  const mean = hs.reduce((s, r) => s + r.errPct, 0) / hs.length;
  const mape = hs.reduce((s, r) => s + Math.abs(r.errPct), 0) / hs.length;
  const worst = hs.reduce((w, r) => (Math.abs(r.errPct) > Math.abs(w) ? r.errPct : w), 0);
  const meanLag = hs.reduce((s, r) => s + r.lagDays, 0) / hs.length;
  console.log(
    `  ${pad(`-${h}d`, 10)}${padS(String(hs.length), 4)}${padS(`${meanLag.toFixed(1)}d`, 10)}${padS(`${mean > 0 ? "+" : ""}${mean.toFixed(2)}%`, 12)}` +
    `${padS(`${mape.toFixed(2)}%`, 10)}${padS(`${worst > 0 ? "+" : ""}${worst.toFixed(2)}%`, 10)}`,
  );
}

const withPred = steps.filter((s) => s.pred).length;
console.log(`\n  ${withPred}/${steps.length} steps produced a prediction · ${steps.length - withPred} abstained`);
console.log(`  NOTE: actuals are RAW finish times. Normalize for conditions before`);
console.log(`        reading a hot race's error as model error (G0.4 stores neutral).\n`);

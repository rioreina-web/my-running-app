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
 * SESSION RESIDUALS (G0.2 in FITNESS-REDESIGN-APPLY.md). Two races is not a
 * loss function. But every quality session is a bounded statement about
 * fitness, and `trainingZoneSignal` already prices one: it asks the athlete's
 * own pace/duration curve what the session's effective duration is worth at
 * the current estimate, and compares that to what was actually run. The anchor
 * cancels out of the ratio, so the comparison is a statement about the
 * ESTIMATE, not about the curve.
 *
 * So: for every quality session in the range, price it against the estimate
 * standing on the last step STRICTLY BEFORE the session's date, and keep the
 * residual. That turns n=2 scoreable races into n=every-workout, and it is the
 * loss function Phase 1 has to beat.
 *
 * Two things that make these residuals honest, and one that does not:
 *
 *   - Strictly out-of-sample. The pricing estimate predates the session, so it
 *     cannot contain it. Late-created rows (106/307 landed >2 days late) are
 *     scored against the estimate that stood BEFORE THE RUN, not before the
 *     upload — a row arriving late is a property of data plumbing, not of how
 *     wrong the model was about the athlete that day.
 *   - Coverage is printed next to error, always. `estimateFromSession` drops
 *     sessions outside the 0.86–1.10 plausibility window, so the residual set
 *     is the model's OWN admission basis. A later model could "win" purely by
 *     admitting fewer, easier sessions — so the rejection census is printed
 *     beside the error table and a drop in `scored` is a red flag, not a
 *     silent improvement. Compare error only at comparable coverage.
 *   - What it is NOT: an unbiased sample of running. It is quality work only,
 *     and only quality work the parser understood.
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
 *   --sessions           list every scored session, not just the summaries
 *   --estimator          ALSO run the Phase-1 estimator and score both side by
 *                        side. Old is untouched; the two chains never interact.
 *   --json               emit the full chain as JSON instead of the tables
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { generateFitnessPrediction, type FitnessPredictionResult, type PriorSnapshotInput }
  from "../supabase/functions/_shared/fitnessPrediction.ts";
import { buildPredictionInput, distanceToRaceType } from "../supabase/functions/_shared/fitnessInputs.ts";
import { estimateFromSession, formatMSS, type ParsedSession }
  from "../supabase/functions/_shared/trainingZoneSignal.ts";
import { estimateFitness, raceObservation, sessionObservation, type Observation }
  from "../supabase/functions/_shared/fitnessEstimator.ts";
import { normalizeRaceTime } from "../supabase/functions/_shared/raceNormalization.ts";
import { equivalentRacePaceSecPerMile, RACE_DISTANCE_MI, type RaceKey }
  from "../supabase/functions/_shared/paces.ts";

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
  /** Conditions-neutral time and how big that correction was — the estimator
   *  prices a race's uncertainty by the size of its own correction. */
  neutralSeconds: number;
  correctionFraction: number;
}

const { data: raceRows, error: raceErr } = await db
  .from("training_logs")
  .select("id, workout_date, race_result, weather_actual")
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
  const key = distanceToRaceType(String(rr.distance)) as unknown as RaceKey;
  const wxRaw = r.weather_actual as { temp_f?: number; dew_point_f?: number } | null;
  const cond = wxRaw && Number.isFinite(Number(wxRaw.temp_f)) && Number.isFinite(Number(wxRaw.dew_point_f))
    ? { tempF: Number(wxRaw.temp_f), dewPointF: Number(wxRaw.dew_point_f), elevationGainM: null }
    : null;
  const neutral = cond ? normalizeRaceTime(rr.finish_time_seconds, key, cond).neutralSeconds : rr.finish_time_seconds;
  races.push({
    date: d, distanceKey: String(rr.distance), actualSeconds: rr.finish_time_seconds, logId: String(r.id),
    neutralSeconds: neutral,
    correctionFraction: (rr.finish_time_seconds - neutral) / rr.finish_time_seconds,
  });
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

/**
 * One quality session priced against the estimate that predated it.
 * `errPct > 0` means the model predicted SLOWER than the athlete ran — the
 * same sign convention as the race table, so the two can be read together.
 */
interface SessionResidual {
  date: string;
  type: string;
  /** Date of the step whose estimate priced it, and how far back that was. */
  pricedFrom: string;
  lagDays: number;
  anchorPace: number;
  neutralWorkPace: number;
  predictedPace: number;
  errPct: number;
  workMinutes: number;
  effectiveMinutes: number;
  repCount: number;
  heatNormalized: boolean;
  confidence: number;
  zoneLabel: string;
}

const chain: PriorSnapshotInput[] = [];
const steps: Step[] = [];

/**
 * Last step strictly before `target`. Mirrors prediction_scores' rule, and is
 * what keeps session residuals out-of-sample: the estimate that priced a
 * session was computed before that session existed.
 */
const stepBefore = (target: Date): Step | null => {
  let best: Step | null = null;
  for (const s of steps) {
    if (parseDay(s.date).getTime() < target.getTime() && s.pred) best = s;
  }
  return best;
};

// ── Phase-1 estimator, run as a SECOND chain (REDESIGN Phase 1) ────────────
// The plan requires old and new side by side over the full history before any
// switch. The two chains share only the input assembly: the new one never
// reads the old one's estimate, and the old one is not modified at all.
const useEstimator = !!args.get("estimator");
const processSd = args.get("process-sd") ? Number(args.get("process-sd")) : undefined;
const observations: Observation[] = [];
const seenObs = new Set<string>();
interface EstStep { date: string; pace: number | null; sd: number | null }
const estSteps: EstStep[] = [];

/** The estimator's own state as of just before `date` — what prices a session. */
const estimateAsOf = (date: string) =>
  estimateFitness({
    observations: observations.filter((o) => o.date < date),
    now: parseDay(date),
    processSdPerWeek: processSd,
  });

const residuals: SessionResidual[] = [];
/** Quality-candidate sessions that produced no residual, by reason. */
const sessionRejections: Array<{ date: string; reason: string }> = [];
/** Sessions already priced — a log stays in the input window for weeks. */
const scoredSessions = new Set<string>();
/** Dates already spoken for by a scored race; a race is an anchor, not training. */
const raceDates = new Set(races.map((r) => r.date));

/**
 * Stable identity for a session. `VoiceLogInput` carries no row id, and an
 * athlete can run twice in a day, so the blocks themselves are the fingerprint.
 */
const sessionKey = (date: string, blocks: readonly { role?: string; durationS?: number | null }[]) =>
  `${date}|${blocks.length}|${blocks.reduce((s, b) => s + (b.durationS ?? 0), 0)}`;

/** The fitted-curve tilt this step's prediction was built with. */
const tiltOf = (p: FitnessPredictionResult): number => {
  const rc = p.diagnostics?.race_curve as { tilt_vs_generic?: number } | undefined;
  return typeof rc?.tilt_vs_generic === "number" ? rc.tilt_vs_generic : 0;
};

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

  // ── Session residuals ───────────────────────────────────────────────────
  // Price every newly-visible quality session against the estimate standing
  // on the last step STRICTLY BEFORE the session was run. `steps` already
  // holds this step, and `stepBefore` is exclusive, so a session dated today
  // is priced by yesterday's estimate — never by one that contains it.
  for (const log of input.extendedVoiceLogs ?? []) {
    const p = log.parsedStructure;
    if (!p || !p.blocks || p.blocks.length === 0) continue;
    const key = sessionKey(log.date, p.blocks);
    if (scoredSessions.has(key)) continue;
    scoredSessions.add(key);

    const prior = stepBefore(parseDay(log.date));
    if (!prior?.pred) {
      // Sessions older than the chain's start have nothing standing before
      // them. Not a model failure — record it so coverage stays honest.
      sessionRejections.push({ date: log.date, reason: "no estimate predates this session" });
      continue;
    }

    const session: ParsedSession = {
      date: log.date,
      type: p.type,
      confidence: p.confidence,
      intentPattern: p.intentPattern ?? null,
      tempF: log.weather?.tempF ?? null,
      dewPointF: log.weather?.dewPointF ?? null,
      blocks: p.blocks,
      declaredRace: raceDates.has(log.date),
    };
    const { estimate, reason } = estimateFromSession(
      session,
      prior.pred.estimated10kPaceSeconds,
      "tenK",
      tiltOf(prior.pred),
    );
    if (!estimate) {
      sessionRejections.push({ date: log.date, reason });
      continue;
    }
    // predicted − actual, so > 0 = model predicted slower than the run.
    const errPct = (estimate.predictedPaceForDuration - estimate.neutralWorkPace)
      / estimate.neutralWorkPace * 100;
    // Second chain: the same session, priced against the ESTIMATOR's own prior
    // state rather than the old engine's, and kept as an observation with a
    // variance instead of a number to be clamped later.
    if (useEstimator) {
      const priorEst = estimateAsOf(log.date);
      if (priorEst) {
        const own = estimateFromSession(session, priorEst.pace, "tenK", 0);
        if (own.estimate) {
          const e = own.estimate;
          observations.push(sessionObservation(
            e.equivalentPace, e.workSeconds / 60, e.ratio, e.confidence, log.date,
            `${p.type ?? "session"} ${Math.round(e.workSeconds / 60)}min`,
          ));
        }
      }
    }

    residuals.push({
      date: log.date,
      // The parser leaves `type` empty on some rows; an unlabelled bucket in
      // the by-type table reads as a formatting glitch rather than as data.
      type: String(p.type ?? "").trim().toLowerCase() || "(untyped)",
      pricedFrom: prior.date,
      lagDays: Math.round((parseDay(log.date).getTime() - parseDay(prior.date).getTime()) / DAY),
      anchorPace: prior.pred.estimated10kPaceSeconds,
      neutralWorkPace: estimate.neutralWorkPace,
      predictedPace: estimate.predictedPaceForDuration,
      errPct,
      workMinutes: estimate.workSeconds / 60,
      effectiveMinutes: estimate.effectiveSeconds / 60,
      repCount: estimate.repCount,
      heatNormalized: estimate.heatNormalized,
      confidence: estimate.confidence,
      zoneLabel: estimate.zoneLabel,
    });
  }

  if (useEstimator) {
    // Races become observations once they are in the past. Priced by the size
    // of their own conditions correction — no exclusion rule.
    for (const r of races) {
      if (r.date >= day(at) || seenObs.has(r.logId)) continue;
      seenObs.add(r.logId);
      const key = distanceToRaceType(r.distanceKey) as unknown as RaceKey;
      if (!key) continue;
      observations.push(raceObservation(
        equivalentRacePaceSecPerMile(key, r.neutralSeconds, "tenK" as RaceKey),
        r.correctionFraction, r.date, `${r.distanceKey.toUpperCase()} race`,
      ));
    }
    const est = estimateFitness({ observations, now: at, processSdPerWeek: processSd });
    estSteps.push({ date: day(at), pace: est?.pace ?? null, sd: est?.sd ?? null });
  }

  done++;
  if (done % 20 === 0) console.error(`  ${done}/${totalSteps} · ${day(at)} · ${pred ? fmt(pred.predicted10kSeconds) : "null"}`);
}

if (args.get("json")) {
  console.log(JSON.stringify({ steps, races, residuals, sessionRejections }, null, 2));
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
console.log(`        reading a hot race's error as model error (G0.4 stores neutral).`);

// ---------------------------------------------------------------------------
// Session residuals — the loss function (G0.2).
// ---------------------------------------------------------------------------

interface Stats { n: number; mean: number; mape: number; median: number; worst: number; slow: number }

const statsOf = (rs: readonly SessionResidual[]): Stats => {
  const e = rs.map((r) => r.errPct).sort((a, b) => a - b);
  const mid = Math.floor(e.length / 2);
  return {
    n: e.length,
    mean: e.reduce((s, x) => s + x, 0) / e.length,
    mape: e.reduce((s, x) => s + Math.abs(x), 0) / e.length,
    median: e.length % 2 ? e[mid] : (e[mid - 1] + e[mid]) / 2,
    worst: e.reduce((w, x) => (Math.abs(x) > Math.abs(w) ? x : w), 0),
    slow: e.filter((x) => x > 0).length,
  };
};

const pct = (x: number) => `${x > 0 ? "+" : ""}${x.toFixed(2)}%`;

/** Group label → residuals, in first-seen order. */
const groupBy = (rs: readonly SessionResidual[], key: (r: SessionResidual) => string) => {
  const m = new Map<string, SessionResidual[]>();
  for (const r of rs) {
    const k = key(r);
    (m.get(k) ?? m.set(k, []).get(k)!).push(r);
  }
  return m;
};

const statTable = (title: string, groups: Map<string, SessionResidual[]>, w = 14) => {
  console.log(`\n  ${title}`);
  console.log(`  ${pad("", w)}${padS("n", 4)}${padS("mean", 10)}${padS("MAPE", 9)}${padS("median", 9)}${padS("worst", 9)}${padS("% slow", 9)}`);
  for (const [label, rs] of groups) {
    if (rs.length === 0) continue;
    const s = statsOf(rs);
    console.log(
      `  ${pad(label, w)}${padS(String(s.n), 4)}${padS(pct(s.mean), 10)}${padS(`${s.mape.toFixed(2)}%`, 9)}` +
      `${padS(pct(s.median), 9)}${padS(pct(s.worst), 9)}${padS(`${Math.round(s.slow / s.n * 100)}%`, 9)}`,
    );
  }
};

console.log(`\n${"═".repeat(78)}`);
console.log(`SESSION RESIDUALS · every quality session priced by the estimate that predated it`);
console.log("═".repeat(78));
console.log(`  error > 0 = model predicted SLOWER than the athlete ran (same sign as races)`);

if (residuals.length === 0) {
  console.log(`\n  no session produced a residual — see the rejection census below`);
} else {
  const all = statsOf(residuals);
  // Residuals are in discovery order, which is neither chronological nor its
  // reverse — a late-created row is discovered long after it was run.
  const dates = residuals.map((r) => r.date).sort();
  console.log(`\n  SCORED ${all.n} sessions · ${dates[0]} → ${dates[dates.length - 1]}`);
  console.log(`  ${pad("MAPE", 22)}${padS(`${all.mape.toFixed(2)}%`, 10)}   ← the number Phase 1 must beat`);
  console.log(`  ${pad("mean error (bias)", 22)}${padS(pct(all.mean), 10)}`);
  console.log(`  ${pad("median error", 22)}${padS(pct(all.median), 10)}`);
  console.log(`  ${pad("worst", 22)}${padS(pct(all.worst), 10)}`);
  console.log(`  ${pad("predicted slow / fast", 22)}${padS(`${all.slow} / ${all.n - all.slow}`, 10)}`);

  statTable(
    "BY SESSION TYPE",
    groupBy([...residuals].sort((a, b) => (a.type < b.type ? -1 : 1)), (r) => r.type),
  );

  // Monthly, oldest first — a model that is drifting shows it here and nowhere
  // else. A single MAPE over eight months averages a June failure into January.
  statTable(
    "BY MONTH",
    groupBy([...residuals].sort((a, b) => (a.date < b.date ? -1 : 1)), (r) => r.date.slice(0, 7)),
  );

  // The heat correction is the single largest adjustment applied to a rep pace,
  // and a third of rows carry no weather at all. Split so it cannot hide.
  statTable(
    "BY HEAT NORMALIZATION",
    groupBy(residuals, (r) => (r.heatNormalized ? "normalized" : "no weather")),
    14,
  );

  if (args.get("sessions")) {
    console.log(`\n  EVERY SCORED SESSION (oldest first)`);
    console.log(
      `  ${pad("date", 12)}${pad("type", 12)}${padS("eff min", 8)}${padS("ran", 8)}${padS("predicted", 10)}` +
      `${padS("error", 9)}  zone / priced from`,
    );
    for (const r of [...residuals].sort((a, b) => (a.date < b.date ? -1 : 1))) {
      console.log(
        `  ${pad(r.date, 12)}${pad(r.type.slice(0, 11), 12)}${padS(r.effectiveMinutes.toFixed(0), 8)}` +
        `${padS(formatMSS(r.neutralWorkPace), 8)}${padS(formatMSS(r.predictedPace), 10)}${padS(pct(r.errPct), 9)}` +
        `  ${r.zoneLabel} / ${r.pricedFrom} (-${r.lagDays}d)${r.heatNormalized ? "" : " · no weather"}`,
      );
    }
  }
}

// Coverage. Printed unconditionally and next to the error, because a model
// that improves its MAPE by admitting fewer sessions has not improved.
console.log(`\n${"─".repeat(78)}`);
console.log("COVERAGE  (a later model may only claim a better MAPE at comparable coverage)");
console.log("─".repeat(78));
const considered = residuals.length + sessionRejections.length;
console.log(`  ${residuals.length}/${considered} parsed sessions scored · ${sessionRejections.length} not priced\n`);

// Bucket by reason, with the numbers stripped out — "only 6 min of work" and
// "only 9 min of work" are one finding, not two.
const census = new Map<string, number>();
for (const r of sessionRejections) {
  const bucket = r.reason
    .replace(/^\d+(\.\d+)?% /, "")
    .replace(/only \d+ min of work \(need \d+\)/, "under the work-minutes floor")
    .replace(/type "[^"]*"/, "non-quality type");
  census.set(bucket, (census.get(bucket) ?? 0) + 1);
}
for (const [reason, n] of [...census].sort((a, b) => b[1] - a[1])) {
  console.log(`  ${padS(String(n), 5)}  ${reason}`);
}
console.log();

// ---------------------------------------------------------------------------
// Side by side: the Phase-1 estimator against the shipped model (REDESIGN §1).
// ---------------------------------------------------------------------------

if (useEstimator) {
  console.log(`${"═".repeat(78)}`);
  console.log("PHASE-1 ESTIMATOR vs SHIPPED MODEL");
  console.log("═".repeat(78));

  const estBefore = (target: Date): EstStep | null => {
    let best: EstStep | null = null;
    for (const e of estSteps) {
      if (parseDay(e.date).getTime() < target.getTime() && e.pace != null) best = e;
    }
    return best;
  };

  // ── gate 1: the races ────────────────────────────────────────────────────
  console.log(`\n  GATE 1 — race errors at -1d (vs RAW; §2.1 neutral basis noted in §6)`);
  console.log(`  ${pad("race", 22)}${padS("actual", 10)}${padS("old", 10)}${padS("new", 10)}${padS("old err", 10)}${padS("new err", 10)}`);
  for (const race of races) {
    const raceDay = parseDay(race.date);
    const o = stepBefore(raceDay);
    const n = estBefore(raceDay);
    if (!o?.pred && !n) continue;
    const key = distanceToRaceType(race.distanceKey) as unknown as RaceKey;
    if (!key) continue;
    const oldP = o?.pred ? predictedFor(o.pred, race.distanceKey) : null;
    // The estimator's state is a 10K-equivalent pace; read it at this distance.
    const newP = n?.pace != null
      ? equivalentRacePaceSecPerMile("tenK" as RaceKey, n.pace * RACE_DISTANCE_MI["tenK" as RaceKey], key) * RACE_DISTANCE_MI[key]
      : null;
    const e = (p: number | null) => p == null ? "—" : `${p > race.actualSeconds ? "+" : ""}${((p - race.actualSeconds) / race.actualSeconds * 100).toFixed(2)}%`;
    console.log(
      `  ${pad(`${race.date} ${race.distanceKey}`, 22)}${padS(fmt(race.actualSeconds), 10)}` +
      `${padS(oldP == null ? "—" : fmt(oldP), 10)}${padS(newP == null ? "—" : fmt(newP), 10)}` +
      `${padS(e(oldP), 10)}${padS(e(newP), 10)}`,
    );
  }

  // ── gate 2: session residuals, scored the SAME way for both ──────────────
  // Re-price every scored session against the estimator's state at the same
  // moment the old chain was priced at, so the two MAPEs are comparable.
  const newErr: number[] = [];
  for (const r of residuals) {
    const n = estBefore(parseDay(r.date));
    if (!n?.pace) continue;
    // The residual is a ratio statement; re-express it against the new level.
    const predicted = r.predictedPace * (n.pace / r.anchorPace);
    newErr.push((predicted - r.neutralWorkPace) / r.neutralWorkPace * 100);
  }
  const mape = (xs: number[]) => xs.reduce((s, x) => s + Math.abs(x), 0) / xs.length;
  const mean = (xs: number[]) => xs.reduce((s, x) => s + x, 0) / xs.length;
  const oldErr = residuals.map((r) => r.errPct);
  console.log(`\n  GATE 2 — session residuals (n=${newErr.length})`);
  console.log(`  ${pad("", 14)}${padS("MAPE", 10)}${padS("bias", 10)}`);
  console.log(`  ${pad("shipped", 14)}${padS(`${mape(oldErr).toFixed(2)}%`, 10)}${padS(`${mean(oldErr) > 0 ? "+" : ""}${mean(oldErr).toFixed(2)}%`, 10)}`);
  console.log(`  ${pad("estimator", 14)}${padS(`${mape(newErr).toFixed(2)}%`, 10)}${padS(`${mean(newErr) > 0 ? "+" : ""}${mean(newErr).toFixed(2)}%`, 10)}`);
  const delta = mape(newErr) - mape(oldErr);
  console.log(`  ${pad("", 14)}${padS(`${delta > 0 ? "+" : ""}${delta.toFixed(2)}pp`, 10)}  ${delta < 0 ? "← estimator better" : "← estimator WORSE"}`);

  // ── gate 3: does the pre-April window actually move? ─────────────────────
  const apr = races.find((r) => r.date.startsWith("2026-04"));
  if (apr) {
    const end = parseDay(apr.date);
    const start = new Date(end.getTime() - 56 * DAY);
    const win = (xs: Array<{ date: string; pace: number | null }>) =>
      xs.filter((x) => x.pace != null && parseDay(x.date) >= start && parseDay(x.date) <= end);
    const o = win(steps.map((s) => ({ date: s.date, pace: s.pred?.estimated10kPaceSeconds ?? null })));
    const n = win(estSteps);
    const span = (xs: Array<{ pace: number | null }>) =>
      xs.length < 2 ? 0 : Math.abs((xs[xs.length - 1].pace! - xs[0].pace!));
    console.log(`\n  GATE 3 — movement across the 56 days before ${apr.date}`);
    console.log(`  ${pad("shipped", 14)}${padS(`${span(o).toFixed(1)}s/mi`, 12)} over ${o.length} steps`);
    console.log(`  ${pad("estimator", 14)}${padS(`${span(n).toFixed(1)}s/mi`, 12)} over ${n.length} steps`);
    console.log(`  (§1.3 measured the shipped model moving ~10s across this window — "materially" means more than that)`);
  }
  console.log();
}

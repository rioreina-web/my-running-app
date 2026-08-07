/**
 * `race_projection` — "What am I on track to run?"
 *
 * Principle V (Adaptation). Reads `athlete_state.fitness_prediction`, which
 * the state builders compute from `fitnessPrediction.ts`. No new math.
 *
 * HARD RULE #7 IS THE WHOLE DESIGN OF THIS FILE. The stored prediction carries
 * a `{low, high, point}` range per distance. We ship **the point estimate, the
 * confidence tier, and the lifetime PR alongside** — never the range. The
 * range was tried and reverted (2026-07-18): a confidence-scaled band read as
 * *too wide and inaccurate*, and a marathon window that beat the athlete's PR
 * at the fast end was worse than one honest estimate. Marathon and half round
 * to the whole minute; shorter races keep their seconds.
 *
 * The goal gap is the fact that actually answers the question a goal-chasing
 * athlete is asking. It is stated as a plain difference — never as "you won't
 * make it", which would be a prediction about the future rather than a reading
 * of the present.
 */

import {
  fetchAthleteState,
  fmtRaceTime,
  raceDistanceMiles,
  raceLabel,
  roundsToMinute,
  type PredictionRange,
} from "./athleteState.ts";
import {
  confidenceFromSamples,
  type Analyzer,
  type AnalyzerCtx,
  type AnalyzerParams,
  type AnalyzerResult,
  type Confidence,
  type FactLine,
} from "./types.ts";

const RACES = ["mile", "5k", "10k", "half", "marathon"];

/** The stored tier vocabulary ("high"/"medium"/"low") → the registry's. */
function tierToConfidence(tier: string | null | undefined): Confidence {
  switch ((tier ?? "").toLowerCase()) {
    case "high": return "high";
    case "medium":
    case "moderate": return "moderate";
    default: return "low";
  }
}

function pickRace(
  ranges: Record<string, PredictionRange>,
  requested: string | null,
  goalRace: string | null,
): string | null {
  const keys = Object.keys(ranges);
  const match = (want: string) =>
    keys.find((k) => k.toLowerCase() === want.toLowerCase()) ?? null;
  if (requested) return match(requested);
  // Default to the race they're actually training for.
  if (goalRace) {
    const g = match(goalRace);
    if (g) return g;
  }
  // Otherwise the longest distance we have a projection for — that's the one
  // an athlete with a goal race is usually asking about.
  for (const r of [...RACES].reverse()) {
    const k = match(r);
    if (k) return k;
  }
  return keys[0] ?? null;
}

interface PrRow {
  distance_key: string;
  pr_seconds: number | null;
  time_is_official: boolean | null;
  race_date: string | null;
}

/**
 * The athlete's personal best at this distance, from the `race_prs` view.
 *
 * `time_is_official` is the field that matters. A PR resting on a watch time
 * is systematically FAST — the watch stops, the race clock doesn't — so a
 * detected-but-unconfirmed result can be tens of seconds quicker than what the
 * athlete actually ran. We surface the number either way and say which it is,
 * rather than quietly presenting moving time as a result.
 */
async function fetchPr(
  ctx: AnalyzerCtx,
  raceKey: string,
): Promise<PrRow | null> {
  const key = raceKey.toLowerCase() === "half_marathon" ? "half" : raceKey.toLowerCase();
  const { data } = await ctx.supabase
    .from("race_prs")
    .select("distance_key, pr_seconds, time_is_official, race_date")
    .eq("user_id", ctx.userId)
    .eq("distance_key", key)
    .maybeSingle();
  const row = (data ?? null) as PrRow | null;
  return row && Number(row.pr_seconds) > 0 ? row : null;
}

export const raceProjection: Analyzer = {
  id: "race_projection",
  label: "What am I on track to run?",
  group: "adaptation",
  params: {
    race: {
      type: "string",
      enum: RACES,
      optional: true,
      describe: "Which distance to project. Omit to use the athlete's goal race.",
    },
  },

  async run(params: AnalyzerParams, ctx: AnalyzerCtx): Promise<AnalyzerResult> {
    const state = await fetchAthleteState(ctx.supabase, ctx.userId);
    const prediction = state?.fitness_prediction;
    const ranges = prediction?.ranges ?? null;

    if (!ranges || Object.keys(ranges).length === 0) {
      return {
        facts: [],
        coverage: { sessionsUsed: 0, windowDays: 0, missing: [], confidence: "low" },
        related: ["zone_trend", "load_balance"],
        empty: {
          eyebrow: "No projection yet",
          nudge:
            "A race projection needs a stretch of training to read from. It appears once there's enough on file, and it firms up as you go.",
          cta: null,
        },
      };
    }

    const requested = typeof params.race === "string" ? params.race : null;
    const key = pickRace(ranges, requested, state?.goal_race ?? null);
    const point = key ? Number(ranges[key]?.point) : NaN;

    if (!key || !isFinite(point) || point <= 0) {
      return {
        facts: [],
        coverage: { sessionsUsed: 0, windowDays: 0, missing: [], confidence: "low" },
        related: ["zone_trend"],
        empty: {
          eyebrow: requested ? `No ${raceLabel(requested)} projection` : "No projection yet",
          nudge:
            "That distance isn't projected from the training on file. The distances closest to what you've been running are the ones that firm up first.",
          cta: null,
        },
      };
    }

    const roundMin = roundsToMinute(key);
    const confidence = tierToConfidence(prediction?.confidence_tier);
    const workouts = Number(prediction?.workout_count ?? 0);

    const facts: FactLine[] = [
      {
        key: "projection",
        label: `Projection · ${raceLabel(key)}`,
        value: fmtRaceTime(point, roundMin),
        tone: "neutral",
      },
      {
        key: "confidence_tier",
        label: "Confidence tier",
        value: (prediction?.confidence_tier ?? "low").toUpperCase(),
        tone: confidence === "high" ? "good" : confidence === "low" ? "watch" : "neutral",
      },
    ];

    // Hard rule #7: the demonstrated PR travels alongside the projection, so a
    // number the athlete has never run is never shown on its own.
    const pr = await fetchPr(ctx, key);
    if (pr?.pr_seconds != null) {
      facts.push({
        key: "lifetime_pr",
        label: `Lifetime PR · ${raceLabel(key)}${
          pr.race_date ? ` · ${String(pr.race_date).slice(0, 4)}` : ""
        }`,
        value: fmtRaceTime(Number(pr.pr_seconds), roundMin),
        delta: pr.time_is_official ? undefined : "watch time",
        tone: "neutral",
      });
    }

    // The gap the athlete actually asked about — stated, not forecast.
    const goalSec = Number(state?.goal_time_seconds ?? 0);
    const goalMatchesRace = state?.goal_race
      ? state.goal_race.toLowerCase().replace(/[\s-]/g, "_").includes(key.toLowerCase())
      : false;
    if (goalSec > 0 && goalMatchesRace) {
      const gap = point - goalSec;
      facts.push({
        key: "goal_gap",
        label: `Goal · ${fmtRaceTime(goalSec, roundMin)}`,
        value: fmtRaceTime(Math.abs(gap), roundMin),
        delta: gap > 0 ? "outside" : "inside",
        tone: gap > 0 ? "watch" : "good",
      });
    }

    const missing: string[] = [];
    if (pr == null) {
      missing.push("no race at this distance on file to anchor on");
    } else if (!pr.time_is_official) {
      // The 47-second class of error: a detected race carries moving time, and
      // moving time flatters. Say so rather than letting it pass as a result.
      missing.push("that PR is a recorded time, not a confirmed finish-line result");
    }
    if (workouts > 0 && workouts < 20) {
      missing.push(`built on ${workouts} sessions`);
    }

    const goal = (state?.active_goals ?? []).find((g) => g?.days_until != null);

    return {
      title: `What am I on track to run at the ${raceLabel(key).toLowerCase()}?`,
      facts,
      series: null,
      coverage: {
        sessionsUsed: workouts,
        windowDays: goal?.days_until != null ? Number(goal.days_until) : 0,
        missing,
        confidence: workouts > 0
          ? confidenceFromSamples(workouts, { high: 30, moderate: 15 })
          : confidence,
      },
      related: ["race_pace_specificity", "zone_trend", "load_balance"],
    };
  },
};

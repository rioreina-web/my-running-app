/**
 * `mood_trend` — "How has my mood actually read?"
 *
 * Principle X (The body). Reads `training_logs.mood` and `daily_checkins.mood`
 * across a window. Mood is stored as a TEXT label from a closed vocabulary
 * (`energized | positive | neutral | tired | struggling | injured`), never as a
 * number — so the athlete's own word survives all the way to the surface.
 *
 * WHY THIS DOESN'T EMIT AN AVERAGE. Averaging a mood vocabulary requires
 * assigning it numbers, and the moment you do that "3.4" becomes the answer
 * instead of "you wrote tired eleven times". The facts here are counts and the
 * most recent label. The distribution is the chart.
 *
 * Coverage is unusually load-bearing for this analyzer: mood is logged on
 * roughly a third of runs for most athletes, so a "trend" over 12 labels in a
 * 90-day window needs to say that plainly or it reads as far more certain
 * than it is.
 */

import { daysAgoISO } from "./data.ts";
import { fetchAthleteState } from "./athleteState.ts";
import {
  type Analyzer,
  type AnalyzerCtx,
  type AnalyzerParams,
  type AnalyzerResult,
  type FactLine,
  type SeriesPoint,
} from "./types.ts";

const DEFAULT_WINDOW_DAYS = 90;
const MIN_LABELS = 5;

/** The closed vocabulary, ordered brightest → hardest. Display order only. */
const MOOD_ORDER = ["energized", "positive", "neutral", "tired", "struggling", "injured"];

/** The half of the vocabulary that reads as hard going. Used for a count, not a score. */
const HARD_MOODS = new Set(["tired", "struggling", "injured"]);

interface MoodRow {
  mood: string | null;
  when: string | null;
}

export const moodTrend: Analyzer = {
  id: "mood_trend",
  label: "How has my mood been reading?",
  group: "body",
  params: {
    window_days: {
      type: "number",
      min: 14,
      max: 365,
      optional: true,
      describe: "How far back to look. Defaults to 90 days.",
    },
  },

  async run(params: AnalyzerParams, ctx: AnalyzerCtx): Promise<AnalyzerResult> {
    const windowDays = Number(params.window_days ?? DEFAULT_WINDOW_DAYS);
    const sinceISO = daysAgoISO(ctx.now, windowDays);
    const sinceDate = sinceISO.slice(0, 10);

    const [{ data: logData }, { data: checkinData }, state] = await Promise.all([
      ctx.supabase
        .from("training_logs")
        .select("mood, workout_date")
        .eq("user_id", ctx.userId)
        .gte("workout_date", sinceISO)
        .order("workout_date", { ascending: true }),
      ctx.supabase
        .from("daily_checkins")
        .select("mood, date")
        .eq("user_id", ctx.userId)
        .gte("date", sinceDate)
        .order("date", { ascending: true }),
      fetchAthleteState(ctx.supabase, ctx.userId),
    ]);

    const rows: MoodRow[] = [
      ...((logData ?? []) as Array<{ mood: string | null; workout_date: string | null }>)
        .map((r) => ({ mood: r.mood, when: r.workout_date })),
      ...((checkinData ?? []) as Array<{ mood: string | null; date: string | null }>)
        .map((r) => ({ mood: r.mood, when: r.date })),
    ].filter((r) => r.mood != null && r.mood !== "" && r.when != null);

    const totalRuns = (logData ?? []).length;

    if (rows.length === 0) {
      return {
        facts: [],
        coverage: { sessionsUsed: 0, windowDays, missing: [], confidence: "low" },
        related: ["load_balance", "niggle_timeline"],
        empty: {
          eyebrow: "No mood logged yet",
          nudge:
            "Mood comes from what you say in a voice log or a check-in. Once a few land, the pattern across a block starts to show.",
          cta: null,
        },
      };
    }

    rows.sort((a, b) => String(a.when).localeCompare(String(b.when)));

    const counts = new Map<string, number>();
    for (const r of rows) {
      const m = String(r.mood).toLowerCase();
      counts.set(m, (counts.get(m) ?? 0) + 1);
    }
    const ranked = [...counts.entries()].sort((a, b) => b[1] - a[1]);
    const [topMood, topCount] = ranked[0];
    const hardCount = rows.filter((r) => HARD_MOODS.has(String(r.mood).toLowerCase())).length;
    const latest = rows[rows.length - 1];

    const facts: FactLine[] = [
      {
        key: "most_common",
        label: "Most logged",
        value: topMood,
        delta: `${topCount} of ${rows.length}`,
        tone: HARD_MOODS.has(topMood) ? "watch" : "good",
      },
      {
        key: "latest",
        label: "Most recent",
        value: String(latest.mood),
        tone: HARD_MOODS.has(String(latest.mood).toLowerCase()) ? "watch" : "good",
      },
      {
        key: "hard_share",
        label: "Logged as tired or harder",
        value: String(hardCount),
        delta: `of ${rows.length}`,
        tone: hardCount > rows.length / 2 ? "watch" : "neutral",
      },
    ];

    // The state builder's own read of the direction, when it has one. Carried
    // rather than recomputed so Ask agrees with every other surface.
    if (state?.mood_trend) {
      facts.push({
        key: "direction",
        label: "Direction",
        value: String(state.mood_trend),
        tone: "neutral",
      });
    }

    // Distribution, in vocabulary order — the shape of the block, not a score.
    const points: SeriesPoint[] = MOOD_ORDER
      .filter((m) => counts.has(m))
      .map((m) => ({ x: m, y: counts.get(m) ?? 0, y2: null, label: m }));

    const missing: string[] = [];
    if (totalRuns > 0) {
      const pct = Math.round((rows.length / totalRuns) * 100);
      if (pct < 60) {
        missing.push(`mood logged on ${pct}% of runs in this window`);
      }
    }
    if (rows.length < MIN_LABELS) {
      missing.push(`only ${rows.length} labels on file`);
    }

    return {
      facts,
      series: points.length > 1
        ? { kind: "bar", unit: "count", invertY: false, band: null, points }
        : null,
      coverage: {
        sessionsUsed: rows.length,
        windowDays,
        missing,
        confidence: rows.length >= 20 ? "high" : rows.length >= MIN_LABELS ? "moderate" : "low",
      },
      related: ["load_balance", "niggle_timeline", "efficiency"],
    };
  },
};

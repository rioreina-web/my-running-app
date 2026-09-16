/**
 * Watch — "How's she feeling, over days and weeks?"
 *
 * Rio's framing, and the word that matters is *over*. A bad Tuesday is
 * nothing. The question is direction: is this athlete trending down across a
 * stretch, and has it stopped being a blip?
 *
 * Distinct from `rules/lowMoodStreak.ts`, which fires on three consecutive
 * low labels. A streak catches a cliff. This catches a slope — the athlete
 * who was energized a month ago, is neutral now, and hasn't had a bad enough
 * day to trip a streak. That slide is the one a coach catches by feel and
 * software usually misses entirely.
 */

import {
  clear,
  daysBetween,
  finding,
  gap,
  moodScore,
  type Watch,
  type WatchContext,
  type WatchResult,
} from "./types.ts";

const WATCH_ID = "recovery_trend";

/** The "how are they now" window. */
const RECENT_DAYS = 10;
/** The baseline it's measured against. */
const BASELINE_DAYS = 35;

/** Enough labels on each side for a mean to mean anything. */
const MIN_RECENT = 3;
const MIN_BASELINE = 4;

/**
 * How far the mean must fall to count as a real slide, on the −2…+2 scale.
 * 0.6 is roughly "most days one step worse" — big enough to clear label
 * noise, small enough to catch the slope before it becomes a streak.
 */
const SLIDE_THRESHOLD = 0.6;

/** Below this, the athlete is in a bad place regardless of direction. */
const ABSOLUTE_FLOOR = -1.0;

export const recoveryTrend: Watch = {
  id: WATCH_ID,
  domain: "recovery",
  question: "How's she feeling, across the last few weeks?",
  reads: ["moodHistory"],

  evaluate(ctx: WatchContext): WatchResult {
    const scored = ctx.moodHistory
      .map((m) => ({ age: daysBetween(m.date, ctx.now), score: moodScore(m.mood) }))
      .filter((m): m is { age: number; score: number } => m.score !== null && m.age >= 0);

    const recent = scored.filter((m) => m.age <= RECENT_DAYS);
    const baseline = scored.filter((m) => m.age > RECENT_DAYS && m.age <= BASELINE_DAYS);

    if (recent.length < MIN_RECENT) {
      return gap(
        WATCH_ID,
        "recovery",
        `Only ${recent.length} mood check-in${recent.length === 1 ? "" : "s"} in the last ${RECENT_DAYS} days — not enough to read how she's feeling.`,
      );
    }

    const mean = (xs: { score: number }[]) =>
      xs.reduce((s, x) => s + x.score, 0) / xs.length;

    const recentMean = mean(recent);
    const lowNow = recentMean <= ABSOLUTE_FLOOR;

    // Without a baseline we can still report an absolute low, but not a slope.
    if (baseline.length < MIN_BASELINE) {
      if (!lowNow) return clear();
      return finding({
        watch_id: WATCH_ID,
        domain: "recovery",
        severity: "med",
        headline: "She's been flat for a stretch.",
        detail:
          `The last ${recent.length} check-ins average out low. There isn't enough history ` +
          `behind them to say whether this is a change or just how this block has felt, ` +
          `so it's worth asking rather than assuming.`,
        evidence: [`${recent.length} check-ins in ${RECENT_DAYS}d, averaging low`],
        suggested: null,
        confidence: "low",
        defer_to_human: true,
      });
    }

    const baselineMean = mean(baseline);
    const drop = baselineMean - recentMean;
    const sliding = drop >= SLIDE_THRESHOLD;

    if (!sliding && !lowNow) return clear();

    const fmt = (v: number) => v.toFixed(1);
    const evidence = [
      `last ${RECENT_DAYS}d mood mean ${fmt(recentMean)} (n=${recent.length})`,
      `prior ${BASELINE_DAYS - RECENT_DAYS}d mean ${fmt(baselineMean)} (n=${baseline.length})`,
      `change ${drop > 0 ? "−" : "+"}${fmt(Math.abs(drop))} on a −2…+2 scale`,
    ];

    // A slide that's also arrived somewhere low is the one to act on. A slide
    // from "great" to "fine" is worth noticing and not worth touching.
    const severity = sliding && lowNow ? "high" : sliding ? "med" : "med";

    const detail = sliding && lowNow
      ? `She's been sliding for a few weeks and has now arrived somewhere low — ` +
        `the recent stretch averages ${fmt(recentMean)} against ${fmt(baselineMean)} before it. ` +
        `This is the point where easing the week costs far less than not easing it.`
      : sliding
      ? `The trend is down — ${fmt(recentMean)} across the last ${RECENT_DAYS} days against ` +
        `${fmt(baselineMean)} over the month before. She isn't in a bad place yet, which is ` +
        `exactly why it's worth a light touch now rather than a heavy one later.`
      : `She's been consistently low across the last ${RECENT_DAYS} days ` +
        `(mean ${fmt(recentMean)}), without a sharp drop to point at. ` +
        `A flat low is easy to miss because nothing about it looks like an event.`;

    return finding({
      watch_id: WATCH_ID,
      domain: "recovery",
      severity,
      headline: sliding ? "She's been trending down." : "She's been flat for a stretch.",
      detail,
      evidence,
      // Ease the week — the lightest move that changes anything.
      suggested: sliding && lowNow ? "reduce_volume" : null,
      confidence: recent.length >= 5 && baseline.length >= 8 ? "high" : "medium",
      defer_to_human: lowNow,
    });
  },
};
